#!/bin/bash

export POSTGRES_DATA_DIR=$HOME/Docker/data

export CLUSTER_DIR=$HOME/Cluster
export SECRETS_DIR=$CLUSTER_DIR/secrets
export PERMANENT_DATA_DIR=$CLUSTER_DIR/permanent_data
export CORE_GATEWAY_HTML_DIR=$PERMANENT_DATA_DIR/core_gateway/html
export CORE_REGISTRY_DATA_DIR=$PERMANENT_DATA_DIR/registry/data
export DATABASE_BACKUP_DIR=$PERMANENT_DATA_DIR/database/backup
export DATABASE_BACKUPS_DIR=$PERMANENT_DATA_DIR/database/backups
export SG_APPLICATION_BIBLE_FILES_DIR=$PERMANENT_DATA_DIR/bibleFiles
export SG_APPLICATION_NODRIGEN_REQUESTS_LOGS_DIR=$PERMANENT_DATA_DIR/sg-application/nodrigenRequests
export SG_APPLICATION_LOGS_DIR=$PERMANENT_DATA_DIR/sg-application/logs
export SG_APPLICATION_GATEWAY_DIR=$PERMANENT_DATA_DIR/sg-application-gateway
export SG_BANKS_LOGS_DIR=$PERMANENT_DATA_DIR/sg-banks/logs

export CORE_DIR=$CLUSTER_DIR/core
export CORE_MANAGEMENT_DIR=$CORE_DIR/management
export CORE_SETUP_DIR=$CORE_DIR/setup
export CORE_STACK_DIR=$CORE_DIR/stack
export CORE_CONFIG_DIR=$CORE_STACK_DIR/config
export REGISTRY_DIR=$CORE_STACK_DIR/registry
export REGISTRY_DATA_DIR=$REGISTRY_DIR/data

export DB_DIR=$CLUSTER_DIR/db
export DB_MANAGEMENT_DIR=$DB_DIR/management
export DB_SETUP_DIR=$DB_DIR/setup
export DB_STACK_DIR=$DB_DIR/stack

export SG_APPLICATION_DIR=$CLUSTER_DIR/sg-application
export SG_APPLICATION_MANAGEMENT_DIR=$SG_APPLICATION_DIR/management
export APPLICATION_STACK_DIR=$SG_APPLICATION_DIR/stack
export APPLICATION_CONFIG_DIR=$APPLICATION_STACK_DIR/config