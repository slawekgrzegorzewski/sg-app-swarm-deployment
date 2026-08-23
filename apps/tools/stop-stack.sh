#!/usr/bin/env bash
set -Eeuo pipefail

stack_name="${1:-}"
case "$stack_name" in
  core|database|application|infrastructure) ;;
  *)
    echo "Usage: $(basename "$0") {core|database|application|infrastructure}" >&2
    exit 2
    ;;
esac

if docker stack ls --format '{{.Name}}' | grep -Fxq "$stack_name"; then
  docker stack rm "$stack_name"
else
  echo "Stack $stack_name is not deployed."
fi
