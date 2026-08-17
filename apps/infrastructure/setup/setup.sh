#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/common/setup/setup_directories.sh

mkdir -p "$SG_APPLICATION_LOGS_DIR"
mkdir -p "$SG_BANKS_LOGS_DIR"
mkdir -p "$CORE_GATEWAY_LOGS_DIR"
mkdir -p "$DATABASE_LOGS_DIR"
mkdir -p "$CLOUDWATCH_STATE_DIR"

MANAGEMENT_DIR=$(realpath $SCRIPT_DIR/../management)

sudo dos2unix $MANAGEMENT_DIR/*.sh
sudo chmod +x $MANAGEMENT_DIR/*.sh

sudo grep -v "$MANAGEMENT_DIR/etherwake.sh" /var/spool/cron/crontabs/slawek | sudo tee /var/spool/cron/crontabs/slawek
echo "* 6 * * * $MANAGEMENT_DIR/etherwake.sh" | sudo tee -a /var/spool/cron/crontabs/slawek

sudo grep -v "$MANAGEMENT_DIR/shutdown.sh" /var/spool/cron/crontabs/slawek | sudo tee /var/spool/cron/crontabs/slawek
echo "0 22 * * * $MANAGEMENT_DIR/shutdown.sh" | sudo tee -a /var/spool/cron/crontabs/slawek

sudo chown slawek:crontab /var/spool/cron/crontabs/slawek
sudo chmod 600 /var/spool/cron/crontabs/slawek
