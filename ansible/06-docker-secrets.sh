#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-home}"
MODE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ansible-wrapper.sh"

resolve_bitwarden_cli() {
  if [[ -n "${BITWARDEN_CLI:-}" ]]; then
    :
  elif command -v bw >/dev/null 2>&1; then
    BITWARDEN_CLI="$(command -v bw)"
  elif command -v bw.exe >/dev/null 2>&1; then
    BITWARDEN_CLI="$(command -v bw.exe)"
  elif command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    local windows_bw_path
    windows_bw_path="$({
      powershell.exe -NoProfile -NonInteractive -Command \
        '(Get-Command bw.exe -ErrorAction Stop).Source'
    } | tr -d '\r')" || true

    if [[ -n "$windows_bw_path" ]]; then
      BITWARDEN_CLI="$(wslpath -u "$windows_bw_path")"
    fi
  fi

  if [[ -z "${BITWARDEN_CLI:-}" ]]; then
    echo "Bitwarden CLI was not found on the Ansible controller." >&2
    echo "Install 'bw' or set BITWARDEN_CLI to its executable path." >&2
    exit 127
  fi

  export BITWARDEN_CLI
  if [[ "$BITWARDEN_CLI" == *.exe ]] && ansible_wrapper_is_windows; then
    case ":${WSLENV:-}:" in
      *:BW_SESSION:*|*:BW_SESSION/*:*) ;;
      *) export WSLENV="${WSLENV:+$WSLENV:}BW_SESSION" ;;
    esac
  fi
}

unlock_bitwarden_vault() {
  if [[ "$MODE" != "apply" || -n "${BW_SESSION:-}" ]]; then
    return
  fi

  if ! BW_SESSION="$("$BITWARDEN_CLI" unlock --raw)"; then
    echo "Nie udało się odblokować sejfu Bitwarden." >&2
    exit 1
  fi
  if [[ -z "$BW_SESSION" ]]; then
    echo "Bitwarden nie zwrócił klucza sesji; Ansible nie zostanie uruchomione." >&2
    exit 1
  fi
  export BW_SESSION
}

case "$MODE" in
  check|apply) ;;
  ""|-h|--help)
    echo "Usage: $(basename "$0") [home|test] [check|apply]"
    echo "Creates or updates unused Docker Swarm secrets from Bitwarden on the manager."
    ansible_wrapper_usage_overrides
    exit 0
    ;;
  *) echo "Unknown mode: $MODE (expected check or apply)" >&2; exit 2 ;;
esac

ansible_wrapper_initialize "$ENVIRONMENT"
resolve_bitwarden_cli
unlock_bitwarden_vault
ansible_wrapper_run playbooks/docker-secrets.yml "$MODE" "${@:3}"
