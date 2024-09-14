#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
MANAGEMENT_DIR=$(realpath $SCRIPT_DIR/../management)

dos2unix $MANAGEMENT_DIR/*.sh
chmod +x $MANAGEMENT_DIR/*.sh

echo "%sudo   ALL=(ALL:ALL) NOPASSWD:$MANAGEMENT_DIR/etherwake.sh ALL" | sudo tee /etc/sudoers.d/etherwake-nopasswd
echo "%sudo   ALL=(ALL:ALL) NOPASSWD:$MANAGEMENT_DIR/shutdown.sh ALL" | sudo tee /etc/sudoers.d/shutdown-nopasswd

echo "0 6 * * * $MANAGEMENT_DIR/etherwake.sh" | sudo tee -a /var/spool/cron/crontabs/wakeup
sudo chown slawek:crontab /var/spool/cron/crontabs/wakeup
sudo chmod 600 /var/spool/cron/crontabs/wakeup

echo "0 22 * * * $MANAGEMENT_DIR/shutdown.sh" | sudo tee -a /var/spool/cron/crontabs/shutdown
sudo chown slawek:crontab /var/spool/cron/crontabs/shutdown
sudo chmod 600 /var/spool/cron/crontabs/shutdown