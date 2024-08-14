#!/bin/bash

#prereqiusites:
# ~/Cluster dir created with cloud_watch_config.json and secrets.zip
# the following secrets documented in a form of variables
USERNAME=$1
MAIN_AWS_ACCOUNT_KEY_ID=$2
MAIN_AWS_ACCOUNT_ACCESS_KEY=$3
LOGS_AWS_ACCOUNT_KEY_ID=$4
LOGS_AWS_ACCOUNT_KEY_ID=$5
POSTGRES_PASSWORD=$6

source ./setup_directories.sh

function setup_sudo {
  sudo echo "$USERNAME    ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USERNAME
  sudo apt-get update
  sudo apt-get install -y unzip dos2unix ca-certificates curl gnupg lsb-release
  sudo echo "$USERNAME    ALL=(ALL:ALL) ALL" | sudo tee /etc/sudoers.d/$USERNAME
}

function setup_secrets_and_files {
  unzip $CLUSTER_DIR/secrets.zip -d $CLUSTER_DIR/secrets
  dos2unix **/*
  chmod +x **/*.sh
}

function install_docker {
  # Add Docker's official GPG key:
  sudo apt-get install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo usermod -aG docker $USERNAME
  sudo su - $USERNAME
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service

  echo "{" | sudo tee /etc/docker/daemon.json
  echo "\"insecure-registries\" : [\"https://grzegorzewski.org:5005\"]" | sudo tee -a /etc/docker/daemon.json
  echo "}" | sudo tee -a /etc/docker/daemon.json
  sudo systemctl restart docker
}

function configure_db {
  sudo apt-get install -y postgresql-client-15
  echo "*:*:*:postgres:$POSTGRES_PASSWORD" | sudo tee $HOME/.pgpass
  sudo chmod 400 $HOME/.pgpass

  echo "0 * * * * $DB_MANAGEMENT_DIR/backup_data.sh" | sudo tee -a /var/spool/cron/crontabs/$USERNAME
  sudo chown slawek:crontab /var/spool/cron/crontabs/$USERNAME
  sudo chmod 600 /var/spool/cron/crontabs/$USERNAME
}

function configure_aws_cli_and_access {
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -rf aws awscliv2.zip

  mkdir -p $HOME/.aws
  echo "[default]" > $HOME/.aws/credentials
  echo "aws_access_key_id = $MAIN_AWS_ACCOUNT_KEY_ID" >>$HOME/.aws/credentials
  echo "aws_secret_access_key = $MAIN_AWS_ACCOUNT_ACCESS_KEY" >>$HOME/.aws/credentials
  echo "[AmazonCloudWatchAgent]" >>$HOME/.aws/credentials
  echo "aws_access_key_id = $LOGS_AWS_ACCOUNT_KEY_ID" >>$HOME/.aws/credentials
  echo "aws_secret_access_key = $LOGS_AWS_ACCOUNT_KEY_ID" >>$HOME/.aws/credentials
  chmod 600 $HOME/.aws/credentials

  echo "[default]" >$HOME/.aws/config
  echo "region = eu-central-1" >>$HOME/.aws/config
  echo "output = json" >>$HOME/.aws/config
  echo "[profile AmazonCloudWatchAgent]" >>$HOME/.aws/config
  echo "region = eu-central-1" >>$HOME/.aws/config
  echo "output = json" >> $HOME/.aws/config
  chmod 600 $HOME/.aws/config

  sudo mkdir -p /etc/systemd/system/docker.service.d/
  sudo touch /etc/systemd/system/docker.service.d/aws-credentials.conf
  sudo echo "[Service]" | sudo tee /etc/systemd/system/docker.service.d/aws-credentials.conf
  sudo echo "Environment=\"AWS_ACCESS_KEY_ID=$LOGS_AWS_ACCOUNT_KEY_ID\"" | sudo tee -a /etc/systemd/system/docker.service.d/aws-credentials.conf
  sudo echo "Environment=\"AWS_SECRET_ACCESS_KEY=$LOGS_AWS_ACCOUNT_KEY_ID\"" | sudo tee -a /etc/systemd/system/docker.service.d/aws-credentials.conf

  sudo systemctl daemon-reload
  sudo service docker restart
}

function configure_aws_agent {
  wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
  sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
  rm amazon-cloudwatch-agent.deb

  sudo cp ./cloud_watch_config.json /opt/aws/amazon-cloudwatch-agent/bin/config.json
  sudo dos2unix /opt/aws/amazon-cloudwatch-agent/bin/config.json
  sudo chmod 755 /opt/aws/amazon-cloudwatch-agent/bin/config.json

  sudo echo "[credentials]" | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/common-config.toml
  sudo echo "        shared_credential_file = \"$HOME/.aws/credentials\"" | sudo tee -a /opt/aws/amazon-cloudwatch-agent/etc/common-config.toml

  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m onPremise -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
  sudo service amazon-cloudwatch-agent start
}

# this should be done on root user on all nodes
setup_sudo

#this section on all nodes
setup_secrets_and_files
install_docker
#after this step do
# docker swarm init on a main node and join the swarm on remaining nodes
# setup_secrets.sh on all nodes
# continue on all nodes
configure_db
configure_aws_cli_and_access
#only on main node
configure_aws_agent