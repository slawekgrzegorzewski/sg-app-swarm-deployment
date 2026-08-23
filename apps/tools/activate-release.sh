#!/usr/bin/env bash
set -Eeuo pipefail

release_id="${1:-}"
if [[ ! "$release_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  echo "Usage: $(basename "$0") RELEASE_ID" >&2
  exit 2
fi

cluster_root="${CLUSTER_ROOT:-/srv/cluster}"
release_directory="$cluster_root/releases/$release_id"
temporary_link="$cluster_root/.current-${release_id}.$$"

if [[ -L "$cluster_root/releases" || -L "$release_directory" || \
      ! -f "$release_directory/.release.sha256" || \
      ! -x "$release_directory/tools/start-all.sh" ]]; then
  echo "Release is missing, incomplete, or unsafe: $release_directory" >&2
  exit 1
fi

exec 9> "$cluster_root/.deploy.lock"
if ! flock -n 9; then
  echo 'Another cluster deployment is already running.' >&2
  exit 1
fi

cleanup() {
  rm -f -- "$temporary_link"
}
trap cleanup EXIT

ln -s "releases/$release_id" "$temporary_link"
mv -Tf -- "$temporary_link" "$cluster_root/current"
trap - EXIT

echo "Activated release $release_id."
"$release_directory/tools/start-all.sh"
