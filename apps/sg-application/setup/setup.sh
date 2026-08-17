#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh

mkdir -p $SG_APPLICATION_LOGS_DIR
sudo chown -R 77777:77777 "$SG_APPLICATION_LOGS_DIR"
mkdir -p $SG_BANKS_LOGS_DIR
sudo chown -R 77777:77777 "$SG_BANKS_LOGS_DIR"
