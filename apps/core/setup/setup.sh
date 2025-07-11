#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh
source $SECRETS_DIR/put_secrets_to_env.sh

mkdir -p $CORE_GATEWAY_HTML_DIR
mkdir -p $CORE_REGISTRY_DATA_DIR

mkdir -p $REGISTRY_DATA_DIR
mkdir -p $WORDPRESS_HTML_DIR

source $SECRETS_DIR/clear_secrets_from_env.sh