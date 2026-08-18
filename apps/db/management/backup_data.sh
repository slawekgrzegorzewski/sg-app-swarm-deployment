#!/bin/bash
set -Eeuo pipefail

BACKUP_DIR=${BACKUP_DIR:-/backups}
DATABASE_HOST=${DATABASE_HOST:-database}
DATABASE_PORT=${DATABASE_PORT:-5432}
DATABASE_USER=${DATABASE_USER:-postgres}
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
ARCHIVE_NAME="postgres-${TIMESTAMP}.tar.gz"
TEMP_DIR=$(mktemp -d "$BACKUP_DIR/.postgres-backup.XXXXXX")

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

export PGPASSWORD
PGPASSWORD=$(cat /run/secrets/postgres_password)
export PGHOST="$DATABASE_HOST"
export PGPORT="$DATABASE_PORT"
export PGUSER="$DATABASE_USER"

echo "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
until pg_isready --dbname=postgres >/dev/null 2>&1; do
  sleep 2
done

mkdir -p "$TEMP_DIR/databases" "$TEMP_DIR/config"

POSTGRES_VERSION=$(psql --dbname=postgres --no-psqlrc --tuples-only --no-align \
  --command="SELECT version();")
{
  echo "created_at=${TIMESTAMP}"
  echo "postgres_version=${POSTGRES_VERSION}"
  echo
  echo "databases:"
} > "$TEMP_DIR/manifest.txt"

pg_dumpall --globals-only > "$TEMP_DIR/globals.sql"

psql --dbname=postgres --no-psqlrc --tuples-only --no-align \
  --command="SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname;" |
while IFS= read -r database_name; do
  [ -n "$database_name" ] || continue
  echo "Dumping database: $database_name"
  printf '%s\n' "- $database_name" >> "$TEMP_DIR/manifest.txt"
  pg_dump --format=custom --dbname="$database_name" \
    --file="$TEMP_DIR/databases/${database_name}.dump"
done

{
  echo
  echo "effective_settings:"
  psql --dbname=postgres --no-psqlrc --tuples-only --no-align \
    --field-separator='=' \
    --command="SELECT name, setting FROM pg_settings WHERE source <> 'default' ORDER BY name;"
} > "$TEMP_DIR/config/effective-settings.txt"

{
  echo "# PostgreSQL pg_hba_file_rules"
  psql --dbname=postgres --no-psqlrc --tuples-only --no-align \
    --field-separator='|' \
    --command="SELECT type, database, user_name, address, auth_method, error FROM pg_hba_file_rules ORDER BY line_number;"
} > "$TEMP_DIR/config/pg-hba-file-rules.txt"

printf '%s\n' "Backup completed at ${TIMESTAMP}" >> "$TEMP_DIR/manifest.txt"

ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
TEMP_ARCHIVE="$BACKUP_DIR/.${ARCHIVE_NAME}.partial"
tar -C "$TEMP_DIR" -czf "$TEMP_ARCHIVE" .
test -s "$TEMP_ARCHIVE"
mv "$TEMP_ARCHIVE" "$ARCHIVE_PATH"

echo "Created backup: $ARCHIVE_PATH"
