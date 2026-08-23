#!/usr/bin/env bash
set -Eeuo pipefail

exec sudo /srv/cluster/bin/renew-certificates "$@"
