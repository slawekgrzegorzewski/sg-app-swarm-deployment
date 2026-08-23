#!/usr/bin/env bash
set -Eeuo pipefail

backup_archive="${BACKUP_ARCHIVE:-}"
if [[ -z "$backup_archive" || ! -s "$backup_archive" ]]; then
  echo "Backup archive does not exist or is empty: $backup_archive" >&2
  exit 1
fi

restore_directory="$(mktemp -d /tmp/postgres-restore.XXXXXX)"
trap 'rm -rf -- "$restore_directory"' EXIT

tar -tzf "$backup_archive" >/dev/null
tar -xzf "$backup_archive" -C "$restore_directory"

export PGPASSWORD
PGPASSWORD="$(cat /run/secrets/postgres_password)"
export PGHOST="${DATABASE_HOST:-database_postgres}"
export PGPORT="${DATABASE_PORT:-5432}"
export PGUSER="${DATABASE_USER:-postgres}"

until pg_isready --dbname=postgres >/dev/null 2>&1; do
  sleep 2
done

globals_restore_log="$restore_directory/config/globals-restore.log"
psql --dbname=postgres --set=ON_ERROR_STOP=0 \
  < "$restore_directory/globals.sql" > "$globals_restore_log" 2>&1

if grep -q '^ERROR:' "$globals_restore_log"; then
  echo 'WARNING: some global objects already existed or could not be restored.' >&2
  cat "$globals_restore_log" >&2
fi

while IFS= read -r dump_file; do
  database_name="$(basename "$dump_file" .dump)"
  echo "Restoring database: $database_name"
  pg_restore \
    --clean \
    --if-exists \
    --create \
    --exit-on-error \
    --dbname=template1 \
    "$dump_file"
done < <(find "$restore_directory/databases" -maxdepth 1 -type f -name '*.dump' -print | sort)

echo 'Restore completed.'
