#!/usr/bin/env bash
set -Eeuo pipefail

exec sudo /usr/local/sbin/renew-application-certs "$@"
