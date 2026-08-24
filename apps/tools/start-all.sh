#!/usr/bin/env bash
set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_directory/start-stack.sh" infrastructure

# Services in the remaining stacks use Alloy as their Docker syslog endpoint.
# `docker stack deploy` returns before the Alloy task has bound TCP/1514, so
# deploying them immediately can make the logging driver fail its first
# connection attempt.
alloy_service="infrastructure_alloy"
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  alloy_state="$(docker service ps --filter desired-state=running \
    --format '{{.CurrentState}}' "$alloy_service" 2>/dev/null || true)"
  if [[ "$alloy_state" == *"Running"* ]]; then
    break
  fi
  sleep 2
done

if [[ "${alloy_state:-}" != *"Running"* ]]; then
  echo "Timed out waiting for $alloy_service to become Running." >&2
  docker service ps "$alloy_service" --no-trunc >&2 || true
  exit 1
fi

for stack_name in core database application; do
  "$script_directory/start-stack.sh" "$stack_name"
done
