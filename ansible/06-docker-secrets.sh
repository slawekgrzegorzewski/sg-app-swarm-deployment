#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-home}"
MODE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ansible-wrapper.sh"

resolve_onepassword_cli() {
  if [[ -n "${ONEPASSWORD_CLI:-}" ]]; then
    return 0
  fi

  if command -v op >/dev/null 2>&1; then
    ONEPASSWORD_CLI="$(command -v op)"
  elif command -v op.exe >/dev/null 2>&1; then
    ONEPASSWORD_CLI="$(command -v op.exe)"
  elif command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    local windows_op_path
    windows_op_path="$({
      powershell.exe -NoProfile -NonInteractive -Command \
        '(Get-Command op.exe -ErrorAction Stop).Source'
    } | tr -d '\r')" || true

    if [[ -n "$windows_op_path" ]]; then
      ONEPASSWORD_CLI="$(wslpath -u "$windows_op_path")"
    fi
  fi

  if [[ -z "${ONEPASSWORD_CLI:-}" ]]; then
    echo "1Password CLI was not found on the Ansible controller." >&2
    echo "Install 'op' or set ONEWPASSWORD_CLI to its executable path." >&2
    exit 127
  fi

  export ONEWPASSWORD_CLI
}

case "$MODE" in
  check|apply) ;;
  ""|-h|--help)
    echo "Usage: $(basename "$0") [home|test] [check|apply]"
    echo "Creates missing Docker Swarm secrets from 1Password on the manager."
    ansible_wrapper_usage_overrides
    exit 0
    ;;
  *) echo "Unknown mode: $MODE (expected check or apply)" >&2; exit 2 ;;
esac

ansible_wrapper_initialize "$ENVIRONMENT"
resolve_onepassword_cli
ansible_wrapper_run \
  playbooks/docker-secrets.yml \
  "$MODE" \
  --extra-vars "docker_swarm_secrets_onepassword_cli=$ONEPASSWORD_CLI"
