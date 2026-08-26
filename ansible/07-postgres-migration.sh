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
    echo "Migrates PostgreSQL to the single host configured in postgres_nodes."
    echo "Update postgres_nodes in the inventory before running this command."
    ansible_wrapper_usage_overrides
    exit 0
    ;;
  *) echo "Unknown mode: $MODE (expected check or apply)" >&2; exit 2 ;;
esac

ansible_wrapper_initialize "$ENVIRONMENT"
ansible_wrapper_run playbooks/migrate-postgres.yml "$MODE"
