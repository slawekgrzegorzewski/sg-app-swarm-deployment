#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $(basename "$0") [--database DATABASE] postgres-YYYY-MM-DDTHH-MM-SSZ.tar.gz" >&2
  exit 2
}

restore_database=""
database_option_seen=false
archive_name=""
while (($#)); do
  case "$1" in
    --database)
      (($# >= 2)) || usage
      [[ "$database_option_seen" == false ]] || usage
      database_option_seen=true
      restore_database="$2"
      shift 2
      ;;
    --database=*)
      [[ "$database_option_seen" == false ]] || usage
      database_option_seen=true
      restore_database="${1#*=}"
      shift
      ;;
    -* )
      usage
      ;;
    *)
      [[ -z "$archive_name" ]] || usage
      archive_name="$1"
      shift
      ;;
  esac
done

[[ -n "$archive_name" ]] || usage
if [[ "$database_option_seen" == true && -z "$restore_database" ]]; then
  usage
fi
if [[ "$archive_name" != "$(basename -- "$archive_name")" || ! "$archive_name" =~ ^postgres-[A-Za-z0-9_.-]+\.tar\.gz$ ]]; then
  echo "Provide a backup filename from /srv/cluster/backups/postgres, not a path." >&2
  exit 2
fi
if [[ -n "$restore_database" && ! "$restore_database" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Invalid database name: $restore_database" >&2
  exit 2
fi

cluster_root="${CLUSTER_ROOT:-/srv/cluster}"
archive_path="$cluster_root/backups/postgres/$archive_name"
if [[ ! -s "$archive_path" || ! -r "$archive_path" ]]; then
  echo "Backup archive does not exist, is empty, or is unreadable: $archive_path" >&2
  exit 1
fi

release_directory="$(readlink -f -- "$cluster_root/current")"
release_id="$(basename -- "$release_directory")"
restore_config="postgres_restore_script_${release_id:0:12}"
service_name="postgres-restore-$(date -u +%Y%m%d%H%M%S)"
restore_uid="$(id -u)"
restore_gid="$(id -g)"

if ! docker config inspect "$restore_config" >/dev/null 2>&1; then
  echo "Docker config $restore_config is missing; deploy the database stack from this release first." >&2
  exit 1
fi

if docker stack ls --format '{{.Name}}' | grep -Fxq application; then
  echo 'Stop the application stack before restoring PostgreSQL:' >&2
  echo "  $cluster_root/current/tools/stop-stack.sh application" >&2
  exit 1
fi

if [[ -n "$restore_database" ]]; then
  read -r -p "Type RESTORE to replace only database '$restore_database' from $archive_name: " confirmation
else
  read -r -p "Type RESTORE to replace all databases from $archive_name: " confirmation
fi
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
  --constraint 'node.role==manager' \
  --network application_network \
  --restart-condition none \
  --user "$restore_uid:$restore_gid" \
  --secret source=postgres_password,target=postgres_password \
  --config source="$restore_config",target=/usr/local/bin/restore-data,uid="$restore_uid",gid="$restore_gid",mode=0550 \
  --mount type=bind,source="$cluster_root/backups/postgres",target=/backups,readonly \
  --env "BACKUP_ARCHIVE=/backups/$archive_name" \
  --env "RESTORE_DATABASE=$restore_database" \
  --entrypoint /bin/bash \
  postgres:18.4 \
  /usr/local/bin/restore-data >/dev/null

echo "Restore service started: $service_name"
for attempt in $(seq 1 300); do
  task_state="$(docker service ps "$service_name" --no-trunc --format '{{.CurrentState}}' | head -n 1)"
  case "$task_state" in
    Complete*) break ;;
    Failed*|Rejected*)
      docker service logs --raw "$service_name" >&2 || true
      echo "Restore service failed: $task_state" >&2
      exit 1
      ;;
  esac
  if (( attempt % 15 == 0 )); then
    echo "Restore still running; latest task state: ${task_state:-not scheduled yet}"
    docker service ps --no-trunc "$service_name" || true
  fi
  sleep 2
done

if [[ "${task_state:-}" != Complete* ]]; then
  docker service logs --raw "$service_name" >&2 || true
  echo 'Timed out waiting for the restore service.' >&2
  exit 1
fi

docker service logs --raw "$service_name"
