#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
CONTAINER_ID=$(docker ps -f name=db_database --quiet)

source $SCRIPT_DIR/../setup/setup_directories.sh
BACKUP_DIR=$PERMANENT_DATA_DIR/database/backup
BACKUPS_DIR=$PERMANENT_DATA_DIR/database/backups

docker exec -it $CONTAINER_ID psql -h localhost -p 5432 -U postgres -w postgres -c 'DROP DATABASE accountant;'
docker exec -it $CONTAINER_ID psql -h localhost -p 5432 -U postgres -w postgres -c 'CREATE DATABASE accountant;'
cp $1 $BACKUP_DIR/backup.sql
docker exec -it $CONTAINER_ID psql accountant -h localhost -U postgres -f /backup/backup.sql
