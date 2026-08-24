#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-home}"
MODE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ansible-wrapper.sh"

case "$MODE" in
  check|apply) ;;
  ""|-h|--help)
    echo "Usage: $(basename "$0") [home|test] [check|apply]"
    echo "Configures cluster, SSH and published-service firewall ports."
    ansible_wrapper_usage_overrides
    exit 0
    ;;
  *) echo "Unknown mode: $MODE (expected check or apply)" >&2; exit 2 ;;
esac

ansible_wrapper_initialize "$ENVIRONMENT"
ansible_wrapper_run playbooks/firewall.yml "$MODE"
