#!/bin/sh
set -eu

export KC_DB_PASSWORD="$(cat /run/secrets/keycloak_db_password)"
export KC_BOOTSTRAP_ADMIN_PASSWORD="$(cat /run/secrets/keycloak_bootstrap_admin_password)"
export KEYCLOAK_GOOGLE_CLIENT_ID="$(cat /run/secrets/keycloak_google_client_id)"
export KEYCLOAK_GOOGLE_CLIENT_SECRET="$(cat /run/secrets/keycloak_google_client_secret)"

exec /opt/keycloak/bin/kc.sh start --import-realm
