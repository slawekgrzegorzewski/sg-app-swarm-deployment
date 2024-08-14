#!/bin/bash

CURRENT_DIR=$(pwd)
SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh
$SCRIPT_DIR/../setup/setup.sh

source $SECRETS_DIR/put_secrets_to_env.sh

$SECRETS_DIR/setup_secrets.sh

APP_DIR=$CLUSTER_DIR/$1
APP_STACK_DIR=$APP_DIR/stack
cd $APP_STACK_DIR || exit

CONFIG_VERSION=`date +"%Y-%m-%d_%H-%M-%S"` docker stack deploy --with-registry-auth -c docker-compose.yml $1

source  $SECRETS_DIR/clear_secrets_from_env.sh

cd $CURRENT_DIR