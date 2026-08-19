#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-home}"
MODE="${2:-}"

case "$ENVIRONMENT" in
  home)
    INVENTORY="$SCRIPT_DIR/inventories/home/hosts.yml"
    DEFAULT_KEY="$HOME/.ssh/rpi3_ed25519"
    ;;
  test)
    INVENTORY="$SCRIPT_DIR/inventories/test/hosts.yml"
    DEFAULT_KEY="$SCRIPT_DIR/../ansible-test/.ssh/slawek_vagrant_ed25519"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT (expected home or test)" >&2
    exit 2
    ;;
esac

TARGET_USER="${ANSIBLE_BOOTSTRAP_USER:-slawek}"
SSH_KEY="${ANSIBLE_BOOTSTRAP_KEY:-$DEFAULT_KEY}"

case "$MODE" in
  check|apply) ;;
  ""|-h|--help)
    cat <<EOF
Usage: $(basename "$0") [home|test] [check|apply]

Environment variables:
  ANSIBLE_BOOTSTRAP_USER  SSH/Ansible user (default: $TARGET_USER)
  ANSIBLE_BOOTSTRAP_KEY   private key path (default: $SSH_KEY)
  ANSIBLE_BOOTSTRAP_LIMIT optional host/group limit (default: all inventory hosts)
EOF
    exit 0
    ;;
  *) echo "Unknown mode: $MODE (expected check or apply)" >&2; exit 2 ;;
esac

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ansible-playbook was not found. Install Ansible first." >&2
  exit 127
}
[[ -r "$SSH_KEY" ]] || { echo "SSH private key not found: $SSH_KEY" >&2; exit 1; }

cd "$SCRIPT_DIR"
ANSIBLE_COMMAND=(
  ansible-playbook playbooks/bootstrap-hosts.yml
  -i "$INVENTORY"
  -u "$TARGET_USER"
  --private-key "$SSH_KEY"
)
if [[ -n "${ANSIBLE_BOOTSTRAP_LIMIT:-}" ]]; then
  ANSIBLE_COMMAND+=(--limit "$ANSIBLE_BOOTSTRAP_LIMIT")
fi
if [[ "$MODE" == "check" ]]; then
  ANSIBLE_COMMAND+=(--check --diff)
fi

ANSIBLE_CONFIG="$SCRIPT_DIR/ansible.cfg" \
  "${ANSIBLE_COMMAND[@]}"
