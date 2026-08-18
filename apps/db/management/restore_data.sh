#!/bin/bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/postgres-YYYY-MM-DDTHH-MM-SSZ.tar.gz" >&2
  exit 1
fi

SCRIPT_DIR=$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/../setup/setup_directories.sh"

BACKUP_ARCHIVE=$(realpath "$1")
if [ ! -s "$BACKUP_ARCHIVE" ]; then
  echo "Backup archive does not exist or is empty: $BACKUP_ARCHIVE" >&2
  exit 1
fi

CONTAINER_ID=$(docker ps \
  --filter label=com.docker.swarm.service.name=db_database \
  --format '{{.ID}}' | head -n 1)
if [ -z "$CONTAINER_ID" ]; then
  echo "The PostgreSQL service container is not running on this node." >&2
  exit 1
fi

RESTORE_DIR="$DATABASE_BACKUPS_DIR/.restore-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RESTORE_DIR"
trap 'rm -rf "$RESTORE_DIR"' EXIT

tar -tzf "$BACKUP_ARCHIVE" >/dev/null
tar -xzf "$BACKUP_ARCHIVE" -C "$RESTORE_DIR"

cat <<'WARNING'
Before continuing, manually stop core and sg-application from the Swarm
manager. The restore will replace every database from the archive and restore
global roles and permissions. The script will not start the applications again.
WARNING
read -r -p "Type RESTORE to continue: " confirmation
if [ "$confirmation" != "RESTORE" ]; then
  echo "Restore cancelled."
  exit 1
fi

GLOBALS_RESTORE_LOG="$RESTORE_DIR/config/globals-restore.log"
docker exec --interactive --user postgres "$CONTAINER_ID" psql \
  --dbname=postgres --set=ON_ERROR_STOP=0 \
  < "$RESTORE_DIR/globals.sql" > "$GLOBALS_RESTORE_LOG" 2>&1

if grep -q '^ERROR:' "$GLOBALS_RESTORE_LOG"; then
  echo "WARNING: some global objects already existed or could not be restored."
  cat "$GLOBALS_RESTORE_LOG" >&2
  echo "Continuing with database restore."
fi

while IFS= read -r dump_file; do
  database_name=$(basename "$dump_file" .dump)
  echo "Restoring database: $database_name"
  docker exec --interactive --user postgres "$CONTAINER_ID" pg_restore \
    --clean --if-exists --create --exit-on-error \
    --dbname=template1 \
    < "$dump_file"
done < <(find "$RESTORE_DIR/databases" -maxdepth 1 -type f -name '*.dump' -print | sort)

echo "Restore completed. Configuration snapshots remain in the archive under config/."
