#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "Usage: $(basename "$0") RELEASE.tar.gz RELEASE_ID [SHA256]" >&2
  exit 2
fi

archive_input="$1"
release_id="$2"
expected_checksum="${3:-}"
cluster_root="${CLUSTER_ROOT:-/srv/cluster}"

if ! archive="$(realpath -- "$archive_input" 2>/dev/null)"; then
  echo "Release archive does not exist: $archive_input" >&2
  exit 1
fi

if [[ ! -s "$archive" ]]; then
  echo "Release archive does not exist or is empty: $archive" >&2
  exit 1
fi

if [[ ! "$release_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  echo "Unsafe release identifier: $release_id" >&2
  exit 2
fi

if (( ${#release_id} > 128 )); then
  echo 'Release identifier is too long.' >&2
  exit 2
fi

if [[ ! "$cluster_root" =~ ^/srv/[A-Za-z0-9._-]+$ || "$cluster_root" == /srv ]]; then
  echo "Refusing to manage unsafe cluster root: $cluster_root" >&2
  exit 2
fi

actual_checksum="$(sha256sum "$archive" | awk '{print $1}')"
if [[ -n "$expected_checksum" && ! "$expected_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then
  echo 'Expected SHA-256 must contain exactly 64 hexadecimal characters.' >&2
  exit 2
fi
expected_checksum="${expected_checksum,,}"
if [[ -n "$expected_checksum" && "$actual_checksum" != "$expected_checksum" ]]; then
  echo "Release checksum mismatch: expected $expected_checksum, got $actual_checksum" >&2
  exit 1
fi

while IFS= read -r archive_entry; do
  case "$archive_entry" in
    /*|../*|*/../*|*/..)
      echo "Unsafe path in release archive: $archive_entry" >&2
      exit 1
      ;;
  esac
done < <(tar -tzf "$archive")

while IFS= read -r archive_metadata; do
  case "${archive_metadata:0:1}" in
    -|d) ;;
    *)
      echo "Release archive contains a link or unsupported entry: $archive_metadata" >&2
      exit 1
      ;;
  esac
done < <(tar -tvzf "$archive")

releases_directory="$cluster_root/releases"
release_directory="$releases_directory/$release_id"
staging_directory="$releases_directory/.${release_id}.tmp"
temporary_link="$cluster_root/.current-${release_id}.$$"

if [[ -L "$cluster_root" || -L "$releases_directory" || -L "$release_directory" ]]; then
  echo 'Cluster root, releases directory, and release target must not be symbolic links.' >&2
  exit 1
fi

if [[ ! -d "$cluster_root" || ! -d "$releases_directory" ]]; then
  echo "Cluster directories are missing; run the Ansible layout playbook first." >&2
  exit 1
fi

if [[ ! -w "$cluster_root" || ! -w "$releases_directory" ]]; then
  echo "Cluster directories are not writable; run the Ansible layout playbook first." >&2
  exit 1
fi

exec 9> "$cluster_root/.deploy.lock"
if ! flock -n 9; then
  echo 'Another cluster deployment is already running.' >&2
  exit 1
fi

cleanup() {
  rm -f -- "$temporary_link"
  if [[ -d "$staging_directory" ]]; then
    rm -rf -- "$staging_directory"
  fi
}
trap cleanup EXIT

if [[ ! -d "$release_directory" ]]; then
  if [[ -e "$staging_directory" ]]; then
    rm -rf -- "$staging_directory"
  fi
  mkdir -m 0755 "$staging_directory"
  tar --no-same-owner --no-same-permissions \
    -xzf "$archive" -C "$staging_directory"

  for required_path in \
    stacks/core.yml \
    stacks/database.yml \
    stacks/application.yml \
    stacks/infrastructure.yml \
    tools/start-all.sh; do
    if [[ ! -f "$staging_directory/$required_path" ]]; then
      echo "Release is missing $required_path" >&2
      exit 1
    fi
  done

  find "$staging_directory/tools" -type f -name '*.sh' -exec chmod 0755 {} +

  export CONFIG_VERSION="${release_id:0:12}"
  for stack_file in "$staging_directory"/stacks/*.yml; do
    docker stack config --compose-file "$stack_file" >/dev/null
  done

  printf '%s\n' "$actual_checksum" > "$staging_directory/.release.sha256"
  mv -- "$staging_directory" "$release_directory"
else
  if [[ ! -f "$release_directory/.release.sha256" || \
        "$(cat "$release_directory/.release.sha256")" != "$actual_checksum" ]]; then
    echo "Release ID $release_id already exists with different content." >&2
    exit 1
  fi
  echo "Release $release_id is already installed; activating the existing copy."
fi

ln -s "releases/$release_id" "$temporary_link"
mv -Tf -- "$temporary_link" "$cluster_root/current"
trap - EXIT

echo "Activated release $release_id ($actual_checksum)."

legacy_stacks=(sg-application db db_mysql)
removed_legacy_stack=false
for legacy_stack in "${legacy_stacks[@]}"; do
  if docker stack ls --format '{{.Name}}' | grep -Fxq "$legacy_stack"; then
    docker stack rm "$legacy_stack"
    removed_legacy_stack=true
  fi
done

if "$removed_legacy_stack"; then
  for _ in $(seq 1 120); do
    legacy_stack_still_present=false
    for legacy_stack in "${legacy_stacks[@]}"; do
      if docker stack ls --format '{{.Name}}' | grep -Fxq "$legacy_stack"; then
        legacy_stack_still_present=true
        break
      fi
    done
    "$legacy_stack_still_present" || break
    sleep 1
  done

  if "$legacy_stack_still_present"; then
    echo 'Timed out while removing legacy stacks.' >&2
    exit 1
  fi
fi

"$release_directory/tools/start-all.sh"

if docker network inspect sg_app_network >/dev/null 2>&1 && \
   docker network rm sg_app_network >/dev/null 2>&1; then
  echo 'Removed unused legacy overlay network: sg_app_network'
fi
