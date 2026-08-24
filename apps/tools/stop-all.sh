#!/usr/bin/env bash
set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for stack_name in infrastructure core application database; do
  "$script_directory/stop-stack.sh" "$stack_name"
done
