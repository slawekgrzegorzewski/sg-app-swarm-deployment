#!/bin/bash

CURRENT_DIR=$(pwd)
SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh
$SCRIPT_DIR/../setup/setup.sh

$SECRETS_DIR/setup_secrets.sh

APP_DIR=$CLUSTER_DIR/$1
APP_STACK_DIR=$APP_DIR/stack
cd $APP_STACK_DIR || exit

CONFIG_VERSION=`date +"%Y-%m-%d_%H-%M-%S"` docker stack deploy -c docker-compose.yml $1

cd $CURRENT_DIR