#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
CONTAINER_ID=$(docker ps -f name=db_database --quiet)
FILE_NAME=database_`date +"%Y-%m-%d_%H-%M-%S"`.sql
BANKS_FILE_NAME=banks_database_`date +"%Y-%m-%d_%H-%M-%S"`.sql

source $SCRIPT_DIR/../setup/setup_directories.sh
BACKUP_DIR=$PERMANENT_DATA_DIR/database/backup
BACKUPS_DIR=$PERMANENT_DATA_DIR/database/backups
BANKS_BACKUPS_DIR=$PERMANENT_DATA_DIR/database/banks_backups

docker exec $CONTAINER_ID pg_dump accountant -h localhost -U postgres -f /backup/$FILE_NAME
gzip -9 -c $BACKUP_DIR/$FILE_NAME > $BACKUPS_DIR/$FILE_NAME.gz
rm -f $BACKUP_DIR/$FILE_NAME

docker exec $CONTAINER_ID pg_dump banks -h localhost -U postgres -f /backup/$BANKS_FILE_NAME
gzip -9 -c $BACKUP_DIR/$BANKS_FILE_NAME > $BANKS_BACKUPS_DIR/$BANKS_FILE_NAME.gz
rm -f $BACKUP_DIR/$BANKS_FILE_NAME