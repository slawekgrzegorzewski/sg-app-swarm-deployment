# Keycloak

Keycloak is the source of users, authentication, and authorization metadata
for the applications in this cluster. It is available at
`https://auth.grzegorzewski.pl` and uses the `sg` realm.

The initial realm is imported only when it does not yet exist. This protects
accounts and configuration changed through the admin console during later
deployments. Treat [`../configs/application/sg-realm.json`](../configs/application/sg-realm.json)
as the bootstrap definition, not as a mechanism for overwriting a live realm.

The `sg-test` realm has the same roles, groups, and OIDC clients, with the
`sg-frontend` client restricted to `http://localhost:3000/*` for local frontend
development. Its issuer is
`https://auth.grzegorzewski.pl/realms/sg-test`. It is imported on Keycloak
startup only if `sg-test` does not already exist; changes to the JSON do not
update an existing realm.

## Authorization model

The `groups` claim is the source of a user's scoped permissions. Create groups
using these paths and assign users to their leaf groups:

| Meaning | Group path |
| --- | --- |
| administrator in domain `acme` | `/domains/acme/ADMIN` |
| regular user in domain `acme` | `/domains/acme/USER` |
| access to the accountant application | `/applications/accountant` |

Assign the realm role `ADMIN` or `USER` to the corresponding domain-level
group for broad UI permissions. Backend authorization must always inspect the
complete group path as well, so being an administrator in one domain cannot
authorize a request for another domain. Application access is granted only by
membership in its `/applications/<application>` group.

The imported `sg-frontend` client is a public OIDC Authorization Code + PKCE
client for `https://grzegorzewski.pl`. It emits `groups` in ID, access, and
userinfo tokens. `sg-api` represents the backend resource server and is an
audience in access tokens issued to `sg-frontend`.

## Application migration

Migrate the frontend to use issuer discovery at:

```text
https://auth.grzegorzewski.pl/realms/sg/.well-known/openid-configuration
```

Migrate the Spring backend to validate access tokens from the same issuer, map
the `groups` claim, and enforce both an application group and the requested
domain-level group. Do not enable Spring's resource-server configuration only
in the deployment template: the backend's endpoints need explicit public and
protected route rules first. The existing `jwt_secret_code` flow remains in
place until that application migration is deployed.

## Required secrets

Add these two entries to the `SG App secrets` 1Password item before running
the Docker-secrets playbook:

| Secret | Purpose |
| --- | --- |
| `keycloak_db_password` | password of the PostgreSQL role `keycloak` |
| `keycloak_bootstrap_admin_password` | one-time bootstrap administrator password |

The database initializer creates the `keycloak` role and database
idempotently. PostgreSQL's scheduled backup already includes that database and
its role. The bootstrap account is created only while Keycloak creates the
`master` realm; create a permanent administrator in the admin console, enable
MFA as appropriate, and then delete the temporary `bootstrap-admin` account.

## First deployment

Point the DNS record for `auth.grzegorzewski.pl` at the gateway before renewing
the certificate. Add the required 1Password fields, run the Docker-secrets
playbook, and apply the Let's Encrypt role so the certificate contains the new
hostname. A normal release deployment then starts the database initializer and
Keycloak. After it is available, create the permanent administrator and add
the domain and application groups needed by the applications.
