#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh

mkdir -p $DATABASE_BACKUP_DIR
mkdir -p $DATABASE_ACCOUNTANT_BACKUPS_DIR
mkdir -p $DATABASE_BANKS_BACKUPS_DIR
mkdir -p $DATABASE_SMART_HOME_BACKUPS_DIR
mkdir -p $POSTGRES_DATA_DIR