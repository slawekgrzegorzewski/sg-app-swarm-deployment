#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-home}"
MODE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ansible-wrapper.sh"
ansible_wrapper_initialize "$ENVIRONMENT"

case "$MODE" in
  apply) ;;
  ""|-h|--help)
    echo "Usage: $(basename "$0") [home|test] apply"
    echo "WARNING: this makes all nodes leave the Docker Swarm."
    ansible_wrapper_usage_overrides
    exit 0
    ;;
  *) echo "Only the explicit apply mode is supported for the destructive reset." >&2; exit 2 ;;
esac

ansible_wrapper_run playbooks/docker-swarm-reset.yml "$MODE"
