#!/bin/sh
set -eu

export KC_DB_PASSWORD="$(cat /run/secrets/keycloak_db_password)"
export KC_BOOTSTRAP_ADMIN_PASSWORD="$(cat /run/secrets/keycloak_bootstrap_admin_password)"
export KEYCLOAK_GOOGLE_CLIENT_ID="$(cat /run/secrets/keycloak_google_client_id)"
export KEYCLOAK_GOOGLE_CLIENT_SECRET="$(cat /run/secrets/keycloak_google_client_secret)"
export KEYCLOAK_BREVO_SMTP_PASSWORD="$(cat /run/secrets/brevo_smtp_password)"

/opt/keycloak/bin/kc.sh import --dir /opt/keycloak/data/import --override true

exec /opt/keycloak/bin/kc.sh start
