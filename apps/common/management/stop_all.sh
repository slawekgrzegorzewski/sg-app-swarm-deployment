#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/../setup/setup_directories.sh
$CORE_MANAGEMENT_DIR/stop.sh
$DB_MANAGEMENT_DIR/stop.sh
$SG_APPLICATION_MANAGEMENT_DIR/stop.sh