 #!/bin/bash

SCRIPT_DIR=$(dirname -- $(realpath ${BASH_SOURCE}))
source $SCRIPT_DIR/../setup/setup_directories.sh
CONTAINER_ID=$(docker ps -f name=core_registry-server --quiet)

sudo du -xh $CORE_REGISTRY_DATA_DIR --max-depth=1 | sort -h
docker exec $CONTAINER_ID registry garbage-collect /etc/docker/registry/config.yml