# Keycloak

Keycloak przechowuje użytkowników i metadane uwierzytelniania aplikacji
w klastrze. Jest dostępny pod `https://auth.grzegorzewski.pl` i używa realmu `sg`.

Definicje realmów `sg` i `sg-test` w
[`../configs/application/sg-realm.json`](../configs/application/sg-realm.json)
oraz [`../configs/application/sg-test-realm.json`](../configs/application/sg-test-realm.json)
są importowane podczas pierwszego startu przez `start --import-realm`.
Istniejące realmy są pomijane, więc zmiana pliku nie aktualizuje ich automatycznie.
W istniejącej instalacji wprowadzaj zmiany przez Admin Console lub Admin API,
zachowując konta i pozostałą konfigurację. Przed zmianą wykonaj backup bazy.

The `sg-test` realm has the same roles, groups, and OIDC clients, with the
`sg-frontend` client restricted to `http://localhost:3000/*` for local frontend
development. Its issuer is
`https://auth.grzegorzewski.pl/realms/sg-test`.

Oba startowe realmy zawierają Google jako dostawcę tożsamości. Przed wdrożeniem
dodaj pola własne `keycloak_google_client_id` i `keycloak_google_client_secret`
do wpisu `SG App secrets` w Vaultwarden, odczytywanego przez Bitwarden CLI.
W kliencie Google OAuth zarejestruj następujące adresy przekierowań:

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

| Meaning                              | Group path                 |
| ------------------------------------ | -------------------------- |
| administrator in domain `acme`       | `/domains/acme/ADMIN`      |
| regular user in domain `acme`        | `/domains/acme/USER`       |
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

Przed uruchomieniem playbooka sekretów dodaj poniższe pola własne do wpisu
`SG App secrets` w Vaultwarden:

| Secret                               | Purpose                                             |
| ------------------------------------ | --------------------------------------------------- |
| `keycloak_db_password`               | password of the PostgreSQL role `keycloak`          |
| `keycloak_bootstrap_admin_password`  | one-time bootstrap administrator password           |
| `keycloak_google_client_id`          | Google OAuth web client ID                          |
| `keycloak_google_client_secret`      | Google OAuth web client secret                      |
| `keycloak_mcp_chatgpt_client_secret` | Sekret klienta OAuth `sg-mcp-chatgpt`               |
| `brevo_smtp_password`                | Brevo SMTP key used by Keycloak and Spring services |

The database initializer creates the `keycloak` role and database
idempotently. PostgreSQL's scheduled backup already includes that database and
its role. The bootstrap account is created only while Keycloak creates the
`master` realm; create a permanent administrator in the admin console, enable
MFA as appropriate, and then delete the temporary `bootstrap-admin` account.

## Pierwsze wdrożenie

Konfigurację klientów MCP z Authorization Code i PKCE S256, redirect URI ChatGPT,
scope’y i kolejność wdrożenia opisuje [serwer MCP](../../docs/serwer-mcp.md#oauth-21-chatgpt-i-pkce).

Przed odnowieniem certyfikatu skieruj DNS `auth.grzegorzewski.pl` na gateway.
Dodaj wymagane pola własne do wpisu w Vaultwarden, uruchom playbook sekretów
z odblokowaną sesją Bitwarden CLI i zastosuj rolę Let's Encrypt, aby certyfikat
obejmował nową nazwę hosta. Standardowe wdrożenie release'u uruchamia inicjalizator
bazy i Keycloak. Po starcie utwórz stałego administratora oraz grupy domenowe
i aplikacyjne wymagane przez aplikacje.
