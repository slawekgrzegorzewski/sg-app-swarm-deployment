#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh

mkdir -p $SG_APPLICATION_BIBLE_FILES_DIR
mkdir -p $SG_APPLICATION_LOGS_DIR
mkdir -p $SG_APPLICATION_GATEWAY_DIR