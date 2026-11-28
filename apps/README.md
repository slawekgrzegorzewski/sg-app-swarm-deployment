# Swarm release sources

The release inputs are packaged without changing their layout:

```text
stacks/       Docker Swarm Compose files
configs/      files uploaded to Swarm as versioned Docker configs
tools/        manager-only operational commands
```

`application/secrets/setup_secrets.sh` is retained unchanged as a legacy
reference and is deliberately excluded from the archive. `utils/` contains
the release installer used by CI and is transferred next to the archive.
The two scripts under `infrastructure/management` are also legacy references;
the release no longer installs host cron entries.

Runtime directories are not created by these scripts. Ansible derives them
from inventory workload groups under `/srv/cluster`. The release archive is
installed only on the Swarm manager as `/srv/cluster/releases/<release-id>`;
`/srv/cluster/current` points at the active release.

Use `/srv/cluster/current/tools/start-all.sh` to reconcile all stacks or
`start-stack.sh <name>` for one of `core`, `database`, `application`, and
`infrastructure`.

The application stack also contains Keycloak. Its realm model and migration
notes are in [`keycloak/README.md`](keycloak/README.md).

The application stack also contains Keycloak. Its realm model and migration
notes are in [`keycloak/README.md`](keycloak/README.md).

## pgAdmin

Panel jest dostępny pod adresem `https://pgadmin.grzegorzewski.pl`.
Usługa `pgadmin` w stosie `database` korzysta z lokalnego wolumenu na
węźle PostgreSQL. Nginx udostępnia panel przez HTTPS.

1. Skieruj rekord DNS `pgadmin.grzegorzewski.pl` na bramę klastra.
2. Dodaj pole `pgadmin_admin_password` do wpisu Bitwarden z sekretami klastra
   i uruchom `ansible/06-docker-secrets.sh home apply` przed wdrożeniem.
3. Wdróż stosy `core` i `database`, uruchom
   `ansible/05-letsencrypt.sh home apply`, a następnie wykonaj na menedżerze
   `sudo /srv/cluster/bin/renew-certificates`, aby rozszerzyć certyfikat bramy.
4. Zaloguj się jako `slawek@grzegorzewski.pl`. Przy rejestracji serwera
   PostgreSQL użyj hosta `database_postgres`, portu `5432` i danych
   wybranej roli PostgreSQL.

## Próby CROSS przez MCP

MCP odczytuje listę prób i dane do oceny z GraphQL Accountant, w zakresie
zalogowanego użytkownika i domeny. [Konfiguracja i kolejność wdrożenia](../docs/serwer-mcp.md#narzędzia-cross-i-przejście-z-automatycznej-oceny).
