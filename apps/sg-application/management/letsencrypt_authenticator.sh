#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh

LETSENCRYPT_DIR=$SG_APPLICATION_GATEWAY_DIR/letsencrypt
mkdir $LETSENCRYPT_DIR

echo $CERTBOT_VALIDATION > $LETSENCRYPT_DIR/$CERTBOT_TOKEN