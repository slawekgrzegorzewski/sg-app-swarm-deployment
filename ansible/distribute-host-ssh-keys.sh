#!/usr/bin/env bash
set -Eeuo pipefail

# Installs only the private key belonging to each target host. It assumes that
# every corresponding public key is already present in every target's
# ~/.ssh/authorized_keys, or that ANSIBLE_TARGET_KEY provides bootstrap access.

KEY_DIR="${ANSIBLE_HOME_SSH_DIR:-$HOME/.ssh/ansible-home}"
TARGET_USER="${ANSIBLE_TARGET_USER:-slawek}"
BOOTSTRAP_KEY="${ANSIBLE_TARGET_KEY:--}"
MODE="${1:-}"
FORCE="${2:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") apply [--force]

Copies only each host's own private/public key pair from:
  $KEY_DIR

Hosts and key names:
  PC2  -> pc2_ed25519
  rpi5 -> rpi5_ed25519
  rpi4 -> rpi4_ed25519
  rpi3 -> rpi3_ed25519

Without --force, the script refuses to overwrite an existing private key on a target.
EOF
}

case "$MODE" in
  apply) ;;
  ""|-h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [[ -n "$FORCE" && "$FORCE" != "--force" ]]; then
  usage >&2
  exit 2
fi

[[ -d "$KEY_DIR" ]] || { echo "SSH key directory not found: $KEY_DIR" >&2; exit 1; }

copy_host_key() {
  local host="$1"
  local key_name="$2"
  local private_key="$KEY_DIR/$key_name"
  local public_key="$private_key.pub"
  local auth_key="$private_key"
  local -a ssh_options=(-o IdentitiesOnly=yes)

  [[ -r "$private_key" && -r "$public_key" ]] || {
    echo "Missing key pair for $host: $private_key(.pub)" >&2
    return 1
  }

  if [[ "$BOOTSTRAP_KEY" != '-' ]]; then
    [[ -r "$BOOTSTRAP_KEY" ]] || {
      echo "ANSIBLE_TARGET_KEY is not readable: $BOOTSTRAP_KEY" >&2
      return 1
    }
    auth_key="$BOOTSTRAP_KEY"
  fi

  ssh_options+=(-i "$auth_key")

  if ssh "${ssh_options[@]}" "$TARGET_USER@$host" \
    "test -e \"\$HOME/.ssh/ansible-home/$key_name\""; then
    if [[ "$FORCE" != "--force" ]]; then
      echo "Refusing to overwrite $host:~/.ssh/ansible-home/$key_name (use --force to replace it)." >&2
      return 1
    fi
  fi

  ssh "${ssh_options[@]}" "$TARGET_USER@$host" \
    'install -d -m 700 "$HOME/.ssh/ansible-home"'

  scp "${ssh_options[@]}" "$private_key" "$public_key" \
    "$TARGET_USER@$host:.ssh/ansible-home/"

  ssh "${ssh_options[@]}" "$TARGET_USER@$host" \
    "chmod 700 \"\$HOME/.ssh/ansible-home\" && chmod 600 \"\$HOME/.ssh/ansible-home/$key_name\" && chmod 644 \"\$HOME/.ssh/ansible-home/$key_name.pub\""

  echo "Installed $key_name on $host."
}

copy_host_key PC2 pc2_ed25519
copy_host_key rpi5 rpi5_ed25519
copy_host_key rpi4 rpi4_ed25519
copy_host_key rpi3 rpi3_ed25519
