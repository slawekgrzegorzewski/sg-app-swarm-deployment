#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh

mkdir -p $DATABASE_BACKUP_DIR
mkdir -p $DATABASE_BACKUPS_DIR
mkdir -p $POSTGRES_DATA_DIR