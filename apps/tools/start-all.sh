#!/usr/bin/env bash
set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for stack_name in database application core infrastructure; do
  "$script_directory/start-stack.sh" "$stack_name"
done
