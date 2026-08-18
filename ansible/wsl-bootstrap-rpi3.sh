#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK="$SCRIPT_DIR/playbooks/bootstrap-rpi3.yml"
ANSIBLE_CONFIG_FILE="$SCRIPT_DIR/ansible.cfg"
TARGET_USER="${RPI3_ANSIBLE_USER:-slawek}"
SSH_KEY="${RPI3_SSH_KEY:-$HOME/.ssh/rpi3_ed25519}"
MODE="${1:-}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [check|apply]

Commands:
  check  Preview changes without applying them
  apply  Apply changes to rpi3

Environment overrides:
  RPI3_ANSIBLE_USER  SSH/Ansible user (default: $TARGET_USER)
  RPI3_SSH_KEY       Private key path (default: $SSH_KEY)
EOF
}

case "$MODE" in
  ""|-h|--help)
    usage
    exit 0
    ;;
  check)
    PLAYBOOK_OPTIONS=(--check --diff)
    ;;
  apply)
    PLAYBOOK_OPTIONS=()
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ansible-playbook was not found. Install Ansible in WSL first." >&2
  exit 127
}

[[ -f "$PLAYBOOK" ]] || {
  echo "Playbook not found: $PLAYBOOK" >&2
  exit 1
}

[[ -r "$SSH_KEY" ]] || {
  echo "SSH private key not found or not readable: $SSH_KEY" >&2
  echo "Set RPI3_SSH_KEY to the correct path if necessary." >&2
  exit 1
}

cd "$SCRIPT_DIR"

ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  ansible-playbook "$PLAYBOOK" \
    -u "$TARGET_USER" \
    --private-key "$SSH_KEY" \
    "${PLAYBOOK_OPTIONS[@]}"
