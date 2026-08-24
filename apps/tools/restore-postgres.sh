#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $(basename "$0") postgres-YYYY-MM-DDTHH-MM-SSZ.tar.gz" >&2
  exit 2
fi

archive_name="$1"
if [[ "$archive_name" != "$(basename -- "$archive_name")" || ! "$archive_name" =~ ^postgres-[A-Za-z0-9_.-]+\.tar\.gz$ ]]; then
  echo "Provide a backup filename from /srv/cluster/backups/postgres, not a path." >&2
  exit 2
fi

cluster_root="${CLUSTER_ROOT:-/srv/cluster}"
release_directory="$(readlink -f -- "$cluster_root/current")"
release_id="$(basename -- "$release_directory")"
restore_config="postgres_restore_script_${release_id:0:12}"
service_name="postgres-restore-$(date -u +%Y%m%d%H%M%S)"

if ! docker config inspect "$restore_config" >/dev/null 2>&1; then
  echo "Docker config $restore_config is missing; deploy the database stack from this release first." >&2
  exit 1
fi

if docker stack ls --format '{{.Name}}' | grep -Fxq application; then
  echo 'Stop the application stack before restoring PostgreSQL:' >&2
  echo "  $cluster_root/current/tools/stop-stack.sh application" >&2
  exit 1
fi

read -r -p "Type RESTORE to replace all databases from $archive_name: " confirmation
if [[ "$confirmation" != RESTORE ]]; then
  echo 'Restore cancelled.'
  exit 1
fi

cleanup() {
  docker service rm "$service_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker service create \
  --name "$service_name" \
  --constraint 'node.labels.workload.postgres==true' \
  --network application_network \
  --restart-condition none \
  --user 1000:1000 \
  --secret source=postgres_password,target=postgres_password \
  --config source="$restore_config",target=/usr/local/bin/restore-data,uid=1000,gid=1000,mode=0550 \
  --mount type=bind,source="$cluster_root/backups/postgres",target=/backups,readonly \
  --env "BACKUP_ARCHIVE=/backups/$archive_name" \
  --entrypoint /bin/bash \
  postgres:18.4 \
  /usr/local/bin/restore-data >/dev/null

for _ in $(seq 1 300); do
  task_state="$(docker service ps "$service_name" --no-trunc --format '{{.CurrentState}}' | head -n 1)"
  case "$task_state" in
    Complete*) break ;;
    Failed*|Rejected*)
      docker service logs --raw "$service_name" >&2 || true
      echo "Restore service failed: $task_state" >&2
      exit 1
      ;;
  esac
  sleep 2
done

if [[ "${task_state:-}" != Complete* ]]; then
  docker service logs --raw "$service_name" >&2 || true
  echo 'Timed out waiting for the restore service.' >&2
  exit 1
fi

docker service logs --raw "$service_name"
