#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOCAL_ROOT=/development
readonly REMOTE_HOST="${REMOTE_HOST:-192.168.20.2}"
readonly REMOTE_USER="${REMOTE_USER:-slawek}"
readonly REMOTE_PORT="${REMOTE_PORT:-22}"
readonly REMOTE_BACKUP_ROOT="${REMOTE_BACKUP_ROOT:-/srv/cluster/backups}"
readonly SSH_PASSWORD_FILE="${SSH_PASSWORD_FILE:-$LOCAL_ROOT/ssh_pass}"
readonly REMOTE_SUDO_PASSWORD_FILE="${REMOTE_SUDO_PASSWORD_FILE:-$SSH_PASSWORD_FILE}"
readonly KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE:-$LOCAL_ROOT/known_hosts}"
readonly SYNC_S3="${SYNC_S3:-true}"
readonly AWS_S3_BUCKET="${AWS_S3_BUCKET:-intellectualpropertytask}"

readonly POSTGRES_DIRECTORY="$LOCAL_ROOT/POSTGRES"
readonly GRAFANA_DIRECTORY="$LOCAL_ROOT/GRAFANA"
readonly REMOTE_TARGET="$REMOTE_USER@$REMOTE_HOST"

declare -a SSH_COMMAND=(
  ssh
  -p "$REMOTE_PORT"
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$KNOWN_HOSTS_FILE"
  -o GlobalKnownHostsFile=/dev/null
)

if [[ -f "$SSH_PASSWORD_FILE" ]]; then
  SSH_COMMAND=(sshpass -f "$SSH_PASSWORD_FILE" "${SSH_COMMAND[@]}")
fi

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

validate_configuration() {
  [[ "$REMOTE_PORT" =~ ^[0-9]{1,5}$ ]] || fail 'REMOTE_PORT must be a TCP port number.'
  [[ "$REMOTE_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || fail 'REMOTE_HOST contains unsupported characters.'
  [[ "$REMOTE_USER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail 'REMOTE_USER contains unsupported characters.'
  [[ "$REMOTE_BACKUP_ROOT" == /* && "$REMOTE_BACKUP_ROOT" != *"'"* ]] || \
    fail 'REMOTE_BACKUP_ROOT must be an absolute path without quotes.'

  if [[ ! -f "$SSH_PASSWORD_FILE" ]]; then
    log "SSH password file not found; using the SSH key mounted in $LOCAL_ROOT/.ssh."
  fi

  mkdir -p -- "$POSTGRES_DIRECTORY" "$GRAFANA_DIRECTORY"
  mkdir -p -- "$(dirname -- "$KNOWN_HOSTS_FILE")"
  touch "$KNOWN_HOSTS_FILE"
}

remote() {
  "${SSH_COMMAND[@]}" "$REMOTE_TARGET" "$1"
}

remote_sudo() {
  local remote_command="$1"
  local quoted_command
  quoted_command="$(printf '%q' "$remote_command")"

  if [[ -f "$REMOTE_SUDO_PASSWORD_FILE" ]]; then
    # The password is passed only to sudo's standard input. It is never put in
    # the command line or written to the logs.
    { cat -- "$REMOTE_SUDO_PASSWORD_FILE"; printf '\n'; } | \
      "${SSH_COMMAND[@]}" "$REMOTE_TARGET" "sudo -S -p '' /bin/sh -c $quoted_command"
  else
    remote "sudo -n /bin/sh -c $quoted_command"
  fi
}

delete_remote_if_unchanged() {
  local remote_file="$1"
  local expected_checksum="$2"
  local use_sudo="$3"
  local command

  command="actual=\$(sha256sum -- '$remote_file' | awk '{print \$1}'); test \"\$actual\" = '$expected_checksum' && rm -- '$remote_file'"
  if [[ "$use_sudo" == true ]]; then
    remote_sudo "$command"
  else
    remote "$command"
  fi
}

download_file() {
  local source_name="$1"
  local remote_file="$2"
  local local_directory="$3"
  local use_sudo="$4"
  local filename="$5"
  local local_file="$local_directory/$filename"
  local temporary_file=''
  local local_checksum
  local transfer_command="cat -- '$remote_file'"

  if [[ -e "$local_file" ]]; then
    local_checksum="$(sha256sum -- "$local_file" | awk '{print $1}')"
    log "$source_name/$filename already exists locally; verifying it before removing the remote copy."
  else
    temporary_file="$(mktemp "$local_directory/.${filename}.XXXXXX.partial")"
    if [[ "$use_sudo" == true ]]; then
      remote_sudo "$transfer_command" > "$temporary_file" || {
        rm -f -- "$temporary_file"
        fail "Could not download $source_name/$filename"
      }
    else
      remote "$transfer_command" > "$temporary_file" || {
        rm -f -- "$temporary_file"
        fail "Could not download $source_name/$filename"
      }
    fi

    [[ -s "$temporary_file" ]] || {
      rm -f -- "$temporary_file"
      fail "Downloaded file is empty: $source_name/$filename"
    }
    local_checksum="$(sha256sum -- "$temporary_file" | awk '{print $1}')"
    mv -- "$temporary_file" "$local_file"
    log "Downloaded $source_name/$filename"
  fi

  # A remote file is deleted only when its present checksum still equals the
  # local copy. This also protects against a file changing during download.
  delete_remote_if_unchanged "$remote_file" "$local_checksum" "$use_sudo"
  log "Verified and removed remote $source_name/$filename"
}

sync_source() {
  local source_name="$1"
  local remote_directory="$2"
  local filename_pattern="$3"
  local filename_regex="$4"
  local local_directory="$5"
  local use_sudo="$6"
  local find_command
  local file_list
  local filenames=()
  local filename

  find_command="find -- '$remote_directory' -maxdepth 1 -type f -name '$filename_pattern' -printf '%f\\n' | sort"
  if [[ "$use_sudo" == true ]]; then
    if ! file_list="$(remote_sudo "$find_command")"; then
      fail "Could not list remote $source_name backups in $remote_directory"
    fi
  else
    if ! file_list="$(remote "$find_command")"; then
      fail "Could not list remote $source_name backups in $remote_directory"
    fi
  fi

  [[ -n "$file_list" ]] || {
    log "No $source_name backups available on the remote host."
    return
  }
  mapfile -t filenames <<< "$file_list"

  for filename in "${filenames[@]}"; do
    [[ "$filename" =~ $filename_regex ]] || fail "Refusing unexpected remote filename: $filename"
    download_file "$source_name" "$remote_directory/$filename" "$local_directory" "$use_sudo" "$filename"
  done
}

sync_s3() {
  [[ "$SYNC_S3" == true ]] || return

  require_command aws
  log "Synchronizing s3://$AWS_S3_BUCKET to $LOCAL_ROOT/S3"
  aws s3 sync --delete "s3://$AWS_S3_BUCKET" "$LOCAL_ROOT/S3"
  rm -rf -- "$LOCAL_ROOT/S3cpy"
  cp -a -- "$LOCAL_ROOT/S3" "$LOCAL_ROOT/S3cpy"
}

main() {
  require_command ssh
  require_command sha256sum
  require_command mktemp
  if [[ -f "$SSH_PASSWORD_FILE" ]]; then
    require_command sshpass
  fi
  validate_configuration

  log "Downloading PostgreSQL backups from $REMOTE_TARGET"
  sync_source \
    postgres "$REMOTE_BACKUP_ROOT/postgres" 'postgres-*.tar.gz' \
    '^postgres-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z\.tar\.gz$' \
    "$POSTGRES_DIRECTORY" false

  # Grafana's SQLite backups are root-readable on the manager. The transfer
  # therefore uses sudo over SSH, while keeping the files private on the host.
  log "Downloading Grafana backups from $REMOTE_TARGET"
  sync_source \
    grafana "$REMOTE_BACKUP_ROOT/grafana" 'grafana-*.db' \
    '^grafana-[0-9]{8}T[0-9]{6}Z\.db$' \
    "$GRAFANA_DIRECTORY" true

  sync_s3
  log 'Backup download completed.'
}

main "$@"
