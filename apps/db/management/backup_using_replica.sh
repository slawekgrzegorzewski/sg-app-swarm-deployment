#!/bin/bash
set -e

export PGPASSWORD=$(cat /run/secrets/postgres_password)
NOW=`date +"%Y-%m-%d_%H-%M-%S"`
ACCOUNTANT_BACKUP_FILE_NAME=accountant_database_$NOW.sql
BANKS_BACKUPS_FILE_NAME=banks_database_$NOW.sql
SMART_HOME_BACKUPS_FILE_NAME=smart_home_database_$NOW.sql

if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  pg_dump accountant -h rpi5 -U postgres -f /backup/$ACCOUNTANT_BACKUP_FILE_NAME
  gzip -9 -c /backup/$ACCOUNTANT_BACKUP_FILE_NAME > /accountant_backups/$ACCOUNTANT_BACKUP_FILE_NAME.gz
  rm -f /backup/$ACCOUNTANT_BACKUP_FILE_NAME

  pg_dump banks -h rpi5 -U postgres -f /backup/$BANKS_BACKUPS_FILE_NAME
  gzip -9 -c /backup/$BANKS_BACKUPS_FILE_NAME > /banks_backups/$BANKS_BACKUPS_FILE_NAME.gz
  rm -f /backup/$BANKS_BACKUPS_FILE_NAME

  pg_dump smart_home -h rpi5 -U postgres -f /backup/$SMART_HOME_BACKUPS_FILE_NAME
  gzip -9 -c /backup/$SMART_HOME_BACKUPS_FILE_NAME > /smart_home_backups/$SMART_HOME_BACKUPS_FILE_NAME.gz
  rm -f /backup/$SMART_HOME_BACKUPS_FILE_NAME
fi