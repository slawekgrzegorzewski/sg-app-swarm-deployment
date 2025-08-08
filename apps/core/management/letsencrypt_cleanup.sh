#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh

LETSENCRYPT_DIR=$CORE_GATEWAY_HTML_DIR/letsencrypt/.well-known/acme-challenge

rm -f $LETSENCRYPT_DIR/$CERTBOT_TOKEN