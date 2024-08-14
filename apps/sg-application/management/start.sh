#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh
source $SECRETS_DIR/put_secrets_to_env.sh
docker login -p $REGISTRY_PASSWORD -u $REGISTRY_USER $REGISTRY_URL
source  $SECRETS_DIR/clear_secrets_from_env.sh

$SCRIPT_DIR/start_stack.sh sg-application