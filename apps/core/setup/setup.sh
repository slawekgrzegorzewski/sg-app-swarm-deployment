#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/setup_directories.sh

mkdir -p $CORE_GATEWAY_HTML_DIR
mkdir -p $CORE_REGISTRY_DATA_DIR
mkdir -p $CORE_GATEWAY_LOGS_DIR
mkdir -p $REGISTRY_DATA_DIR
