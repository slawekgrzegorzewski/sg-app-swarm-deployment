#!/bin/bash
set -e

export PGPASSWORD=$(cat /run/secrets/postgres_replica_password)

if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  echo "Initializing replica via basebackup..."
  pg_basebackup -h rpi5 -U replicator \
    -D /backup/base_$(date +"%Y-%m-%d-%H-%M-%S") \
    -Fp -Xs -P -R
fi

exec docker-entrypoint.sh postgres