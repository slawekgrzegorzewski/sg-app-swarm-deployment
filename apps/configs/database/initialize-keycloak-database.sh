#!/usr/bin/env bash
set -Eeuo pipefail

export PGHOST="${DATABASE_HOST:-database_postgres}"
export PGPORT="${DATABASE_PORT:-5432}"
export PGUSER="${DATABASE_USER:-postgres}"
export PGPASSWORD
PGPASSWORD=$(< /run/secrets/postgres_password)

keycloak_password=$(< /run/secrets/keycloak_db_password)

echo "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
until pg_isready --dbname=postgres >/dev/null 2>&1; do
  sleep 2
done

# psql variable quoting keeps arbitrary password characters out of SQL syntax.
psql --dbname=postgres --no-psqlrc --set=ON_ERROR_STOP=1 \
  --set=keycloak_password="$keycloak_password" <<'SQL'
SELECT format('CREATE ROLE keycloak LOGIN PASSWORD %L', :'keycloak_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak')
\gexec

SELECT 'CREATE DATABASE keycloak OWNER keycloak'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')
\gexec
SQL

echo 'Keycloak database is ready.'
