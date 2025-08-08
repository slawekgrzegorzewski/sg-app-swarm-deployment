#!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))

source $SCRIPT_DIR/../setup/setup_directories.sh

LETSENCRYPT_CERTS_DIR=/etc/letsencrypt/live/grzegorzewski.pl

sudo certbot certonly --manual --preferred-challenges http --manual-auth-hook $CORE_MANAGEMENT_DIR/letsencrypt_authenticator.sh --manual-cleanup-hook $CORE_MANAGEMENT_DIR/letsencrypt_cleanup.sh -d grzegorzewski.pl,be.grzegorzewski.pl,wordpress.grzegorzewski.pl
sudo cp $LETSENCRYPT_CERTS_DIR/privkey.pem $SECRETS_DIR/certs/sgapplication2.key
sudo cp $LETSENCRYPT_CERTS_DIR/fullchain.pem $SECRETS_DIR/certs/sgapplication2.crt
sudo chown slawek:slawek $SECRETS_DIR/certs/sgapplication2.key
sudo chown slawek:slawek $SECRETS_DIR/certs/sgapplication2.crt
sudo chmod 775 $SECRETS_DIR/certs/sgapplication2.key
sudo chmod 775 $SECRETS_DIR/certs/sgapplication2.crt
$SG_APPLICATION_MANAGEMENT_DIR/stop.sh
sleep 5
$SG_APPLICATION_MANAGEMENT_DIR/start.sh