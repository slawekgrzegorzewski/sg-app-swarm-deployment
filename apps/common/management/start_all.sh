#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/../setup/setup_directories.sh
$CORE_MANAGEMENT_DIR/start.sh
sleep 5
$DB_MANAGEMENT_DIR/start.sh
$SG_APPLICATION_MANAGEMENT_DIR/start.sh