# Keycloak

Keycloak is the source of users, authentication, and authorization metadata
for the applications in this cluster. It is available at
`https://auth.grzegorzewski.pl` and uses the `sg` realm.

The `sg` and `sg-test` realm definitions in
[`../configs/application/sg-realm.json`](../configs/application/sg-realm.json)
and [`../configs/application/sg-test-realm.json`](../configs/application/sg-test-realm.json)
are imported with override enabled whenever the Keycloak task starts. Changes
to these files are therefore applied on deployment. The import replaces the
existing realm configuration and can replace data managed through the Admin
Console, including accounts. Back up the Keycloak database before changing
these definitions or restarting Keycloak.

The `sg-test` realm has the same roles, groups, and OIDC clients, with the
`sg-frontend` client restricted to `http://localhost:3000/*` for local frontend
development. Its issuer is
`https://auth.grzegorzewski.pl/realms/sg-test`.

Both bootstrap realm definitions include Google as an identity provider. Add
`keycloak_google_client_id` and `keycloak_google_client_secret` to the
`SG App secrets` 1Password item before deploying. Register these authorized
redirect URIs in the Google OAuth client:

```text
https://auth.grzegorzewski.pl/realms/sg/broker/google/endpoint
https://auth.grzegorzewski.pl/realms/sg-test/broker/google/endpoint
```

The Google credentials are read from Docker secrets by the Keycloak startup
script and substituted into each realm import.

Both realms use Brevo SMTP for verification and password-reset emails. The
`brevo_smtp_password` Docker secret must contain a Brevo SMTP key (not a Brevo
API key); Keycloak reads it at startup and substitutes it into the realm
configuration. The configured sender `noreply@grzegorzewski.pl` must be
verified in Brevo, and the domain should be authenticated there for reliable
delivery. `verifyEmail` is enabled in both realms. Public self-registration
remains disabled in the `sg` realm; administrators can require verification
for managed accounts, and the verification action will be applied during
login as appropriate.

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
| `keycloak_google_client_id` | Google OAuth web client ID |
| `keycloak_google_client_secret` | Google OAuth web client secret |
| `brevo_smtp_password` | Brevo SMTP key used by Keycloak and Spring services |

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
