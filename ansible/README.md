# Ansible

Ansible przygotowuje hosty, Docker Engine, Swarm, katalogi trwałe, firewall,
certyfikaty oraz sekrety. Stacki aplikacyjne są wdrażane osobno z
wersjonowanego release'u znajdującego się wyłącznie na managerze.

## Środowiska i kolejność uruchamiania

Dostępne inventory:

- `inventories/home` — fizyczny klaster `PC2`, `rpi5`, `rpi4`, `rpi3`;
- `inventories/test` — cztery maszyny Vagrant o tych samych logicznych nazwach.

Pełne przygotowanie nowego klastra:

```bash
./01-bootstrap.sh home apply
./02-docker-swarm.sh home apply
./03-docker-swarm-labels.sh home apply
./04-firewall.sh home apply
./05-letsencrypt.sh home apply
./06-docker-secrets.sh home apply
```

Przed krokiem `06` skonfiguruj lokalne Bitwarden CLI dla Vaultwarden i odblokuj
sejf. Instrukcję oraz mapowanie pól zawiera sekcja
[Sekrety z lokalnego Bitwarden](#sekrety-z-lokalnego-bitwarden).

Po kroku `05` i przed pierwszym wdrożeniem stacka `core` należy jednorazowo
uzyskać rzeczywisty certyfikat na managerze poleceniem pokazanym w sekcji
„Let's Encrypt i rotacja certyfikatów”. Dzięki temu powstaną pierwsze sekrety
TLS oraz plik `current-secrets.env`, których wymaga gateway.

Każdy wrapper obsługuje `check` zamiast `apply`. Można ograniczyć wykonanie do
jednego hosta, np.:

```bash
ANSIBLE_TARGET_LIMIT=rpi3 ./01-bootstrap.sh home apply
```

Pierwsze połączenie SSH użytkownika `slawek` musi już działać, a użytkownik
musi mieć bezhasłowe `sudo`.

## Struktura katalogów hosta

Jedynym katalogiem głównym zarządzanym dla klastra jest `/srv/cluster`:

```text
/srv/cluster/
├── releases/<release-id>/
│   ├── stacks/
│   ├── configs/
│   └── tools/
├── current -> releases/<release-id>
├── bin/
├── data/
│   ├── postgres/
│   ├── registry/
│   └── cloudwatch/
├── backups/postgres/
├── logs/
│   └── letsencrypt/
├── certificates/letsencrypt/
│   ├── config/
│   └── work/
└── www/gateway/
```

`cluster_root` jest zdefiniowany raz w `playbooks/group_vars/all.yml`.
Rola `cluster_layout` nie używa składanych zmiennych
`base_host_extra_directories`; wybiera katalogi bezpośrednio na podstawie grup
inventory.

Provisioning nie kopiuje i nie kasuje danych ze starego układu `/srv/*` ani
`~/Cluster`. Przed pierwszym wdrożeniem należy skopiować do nowego drzewa te
dane, które mają zostać zachowane — w szczególności zawartość registry oraz
statyczne pliki gatewaya. Migrację należy wykonywać przy zatrzymanych usługach;
stare katalogi pozostają dostępne jako źródło lub rollback danych.

## Dynamiczne rozmieszczenie usług

Grupy funkcjonalne są jedynym źródłem prawdy dla katalogów i placementu:

| Grupa inventory | Etykieta Swarm |
|---|---|
| `postgres_nodes` | `workload.postgres=true` |
| `registry_nodes` | `workload.registry=true` |
| `gateway_nodes` | `workload.gateway=true` |
| `application_nodes` | `workload.application=true` |
| `vaultwarden_nodes` | `workload.vaultwarden=true` |
| `observability_nodes` | `workload.observability=true` |
| `letsencrypt_hosts` | `workload.letsencrypt=true` |

Aby przenieść workload, należy zmienić hosta w odpowiedniej grupie i wykonać:

```bash
./03-docker-swarm-labels.sh home apply
```

Playbook najpierw utworzy wymagane katalogi, następnie doda nową etykietę i
usunie ją ze starych nodów. Stare katalogi oraz dane nie są automatycznie
kasowane. Dla danych lokalnych ich ewentualne przeniesienie jest osobną,
jawną operacją.

### Migracja PostgreSQL między nodami

Migracja PostgreSQL ma dedykowany, kontrolowany workflow. Najpierw zmień
pojedynczy host w grupie `postgres_nodes` na host docelowy, a następnie wykonaj
preflight:

```bash
./07-postgres-migration.sh home check
```

Właściwą migrację uruchamia:

```bash
./07-postgres-migration.sh home apply
```

Playbook wykrywa źródło z aktualnej etykiety Swarm, provisionuje katalogi na
celu i odmawia nadpisania niepustego katalogu danych. Po potwierdzeniu wstrzymuje
automatyczny transfer backupów, zatrzymuje aplikację, tworzy finalny backup,
kopiuje go z weryfikacją SHA-256 na managera i host docelowy, zatrzymuje bazę,
przełącza etykietę, uruchamia PostgreSQL, odtwarza backup i ponownie uruchamia
aplikację. `1Do momentu ponownego
uruchomienia aplikacji błąd powoduje próbę
automatycznego przywrócenia etykiety oraz usług na źródle. Po dopuszczeniu
nowych zapisów automatyczny rollback nie jest już wykonywany. Harmonogram
transferu jest wznawiany zarówno po sukcesie, jak i próbie rollbacku. Katalog
danych na starym nodzie nie jest usuwany i pozostaje ręcznym punktem rollbacku.

PostgreSQL, registry i gateway mają obecnie dokładnie po jednym nodzie.
`letsencrypt_hosts` musi wskazywać ten sam pojedynczy host co `gateway_nodes` i
musi to być manager Swarma. Dzięki temu lokalny webroot HTTP-01 i certyfikat
znajdują się na hoście gatewaya.

## Docker Swarm

`02-docker-swarm.sh` inicjalizuje jednego managera, dołącza workerów i tworzy
trzy zewnętrzne sieci overlay:

- `cluster_network`;
- `application_network`.
- `observability_network`.

## Obserwowalność

Stack `infrastructure` uruchamia Loki, Alloy, Prometheus, Grafanę oraz
globalne node-exporter i cAdvisor. Docker przekazuje logi usług przez swój
wbudowany driver `syslog` do Alloy na managerze; na Raspberry Pi nie działa
żaden collector Fluent Bit.

Przed pierwszym wdrożeniem dodaj w Vaultwarden pola własne
`grafana_admin_password` i `portainer_admin_password` do wpisu `SG App secrets`,
a następnie wykonaj:

```bash
./02-docker-swarm.sh home apply
./03-docker-swarm-labels.sh home apply
./04-firewall.sh home apply
./06-docker-secrets.sh home apply
```

Pierwszy krok tworzy `observability_network` oraz zapisuje adres managera jako
docelowy endpoint syslog. Grafana i Portainer są dostępne przez gateway pod
`https://grafana.grzegorzewski.pl` i `https://portainer.grzegorzewski.pl`;
port 1514/TCP jest przeznaczony wyłącznie dla nodów klastra. Loki, Prometheus,
Grafana i Portainer nie publikują portów poza Swarm.

### Backup Grafany

Krok `01-bootstrap.sh` instaluje na hostach z grupy `swarm_managers` lokalny,
wykonywalny skrypt `/srv/cluster/bin/backup_grafana.sh` oraz przygotowuje katalog
`/srv/cluster/backups/grafana`. Skrypt jest instalowany wyłącznie na managerach;
sam backup wykonuje się potem bezpośrednio na managerze. Wykorzystuje API
backupu SQLite przez Python, dzięki czemu nie kopiuje wprost aktywnego pliku
`grafana.db` i nie wymaga zatrzymania Grafany. Backup jest zapisywany jako
`/srv/cluster/backups/grafana/grafana-<timestamp>.db`. Bootstrap instaluje i
włącza usługę `cron` na managerze oraz dodaje wpis uruchamiający backup
codziennie o 02:30 czasu lokalnego hosta (`Europe/Warsaw`).

Po wykonaniu bootstrapu na managerze uruchom:

```bash
sudo /srv/cluster/bin/backup_grafana.sh
ls -lh /srv/cluster/backups/grafana/
```

### Przenoszenie backupów PostgreSQL

Backup PostgreSQL powstaje co godzinę na nodzie z grupy `postgres_nodes`.
Bootstrap instaluje na managerze skrypt
`/srv/cluster/bin/transfer_postgres_backups.sh` i wpis crona uruchamiany o
`HH:30`. Skrypt pobiera wszystkie dostępne archiwa jednym wywołaniem `rsync`
do katalogu tymczasowego, porównuje SHA-256 ze źródłem, atomowo publikuje je w
`/srv/cluster/backups/postgres`, a następnie ponownie potwierdza sumę kontrolną
na nodzie bazy przed usunięciem tamtejszych plików. Po przerwanym wykonaniu
istniejące, zgodne archiwum na managerze jest potwierdzane i źródło zostaje
bezpiecznie uprzątnięte przy następnym przebiegu.

Ręczne uruchomienie na managerze:

```bash
sudo -u slawek /srv/cluster/bin/transfer_postgres_backups.sh
```

Jawnie destrukcyjny reset testowego Swarma:

```bash
./02a-docker-swarm-reset.sh test apply
```

`docker_swarm_advertise_addr` musi być lokalnym adresem IP lub nazwą
interfejsu. Inventory testowe używa adresów `192.168.56.x`.

## Sekrety z lokalnego Bitwarden

`06-docker-secrets.sh` używa Bitwarden Password Manager CLI (`bw`), połączonego
z Vaultwarden, na komputerze z Ansible. Manager nie wymaga klienta Bitwarden
ani sesji sejfu. Wartości są przesyłane do managera przez stdin i chronione
przez `no_log`. Helper managera pozostaje pod
`/srv/cluster/bin/create-docker-secrets`.

Źródłem jest jeden wpis `SG App secrets`, z sekretami w polach własnych
(tekstowych lub ukrytych). Mapowanie `name` → `field` znajduje się w
[`roles/docker_swarm_secrets/defaults/main.yml`](roles/docker_swarm_secrets/defaults/main.yml).
Nazwy sekretów Dockera są zachowane. Przykładowo pole `htpasswd` tworzy
`registry_htpasswd`, a pole `jwt_secret_code` tworzy `jwt_secret_code`.
Migracja wpisu z 1Password wymaga zachowania nazw tych pól; skrypt nie kopiuje
ani nie modyfikuje wpisów w sejfie.

Domyślny `docker_swarm_secrets_bitwarden_item` zawiera UUID istniejącego wpisu
`SG App secrets`: `62066329-6ceb-4337-8a1c-6fb6d7d8d62b`. Odczyt po UUID
eliminuje niejednoznaczne dopasowania nazwy i nie wymaga argumentu `-e`.
Edycja wpisu lub jego nazwy nie wymaga zmiany UUID. Usunięcie i ponowne
utworzenie wpisu albo import jako nowej pozycji wymaga aktualizacji identyfikatora.
Można go nadpisać w inventory lub dodatkową zmienną Ansible. Folder osobisty i kolekcja
organizacji mogą zawierać wpis, o ile zalogowane konto ma do niego dostęp.

Jeśli odczyt wpisu kończy się błędem, w terminalu z odblokowaną sesją wykonaj:

```bash
bw list items --search 'SG App secrets' | jq -r '.[] | [.id, .name] | @tsv'
```

Polecenie wypisuje wyłącznie UUID i nazwy, bez pól i wartości sekretów. Aby
użyć innego wpisu niż domyślny, wskaż jego UUID:

```bash
./06-docker-secrets.sh home apply -e 'docker_swarm_secrets_bitwarden_item=UUID_WPISU'
```

Nie wypisuj pełnego wyniku `bw get item` do logów. Rola przechwytuje błąd CLI
z `no_log` i pokazuje tylko rozpoznaną kategorię błędu, bez surowej odpowiedzi.

Jednorazowa konfiguracja klienta (przed zalogowaniem):

```bash
bw config server https://vault.grzegorzewski.pl
bw login
```

Odblokowanie i uruchomienie z katalogu `ansible`:

```bash
export BW_SESSION="$(bw unlock --raw)"
./06-docker-secrets.sh home check
./06-docker-secrets.sh home apply
bw lock
unset BW_SESSION
```

Hasło główne i 2FA podaje się interaktywnie w CLI. Sesja jest dziedziczona
lokalnie przez `BW_SESSION`, bez umieszczania jej w argumentach poleceń,
inventory i na serwerach. Nie uruchamiaj tego przepływu z włączonym śledzeniem
poleceń powłoki ani debugowaniem CLI. Jeśli logujesz się przez API key,
samo `bw login --apikey` nie odblokowuje sejfu — nadal potrzebne jest `bw unlock`.

Wrapper wybiera `bw` z PATH, następnie `bw.exe`; w WSL potrafi znaleźć binarkę
Windows przez PowerShell. `BITWARDEN_CLI` pozwala wskazać inną binarkę. Logowanie
i odblokowanie wykonuj tym samym klientem i profilem co provisioning.
Dla Windowsowego klienta wywoływanego z WSL wrapper przekazuje `BW_SESSION`
przez `WSLENV`. Oddzielny lokalny profil można wybrać przez
`BITWARDENCLI_APPDATA_DIR`, zgodnie z
[dokumentacją Bitwarden CLI](https://bitwarden.com/help/cli/).

Przed odczytem sejfu rola sprawdza serwisy Swarma. Sekret używany przez
usługę jest pomijany. Gdy są sekrety do utworzenia lub aktualizacji, rola wymaga
odblokowanej sesji, wykonuje `bw sync`, a następnie jeden `bw get item`.
Przed pierwszą zmianą w Dockerze sprawdza wszystkie wymagane pola: każde musi
istnieć dokładnie raz i mieć niepustą wartość tekstową. Brak lub duplikat pola
przerywa wykonanie bez zmiany sekretów. Wartości wielowierszowe zachowujemy;
`encoding: base64` nadal dekoduje pole przed wysłaniem do Dockera.

Docker nie udostępnia wartości zapisanego sekretu, dlatego nieużywany
istniejący sekret jest przy każdym `apply` tworzony ponownie. Sekrety usług
aktywnych wymagają osobnej, świadomej rotacji. Tryb `check` sprawdza definicje,
managera i obecność CLI, ale nie synchronizuje ani nie odczytuje sejfu i nie
zmienia sekretów. Nie wymaga odblokowanej sesji.

Stary `apps/application/secrets/setup_secrets.sh` jest wrapperem tego samego
playbooka; przyjmuje te same argumenty `home|test` i `check|apply`. Nie usuwa już
sekretów działających usług i nie tworzy sekretów z dosłownej treści referencji.

Testy adaptera Bitwarden (atrapy CLI i managera, bez dostępu do sejfu):

```bash
python3 -m unittest discover -s tests -p test_bitwarden_secrets.py -v
```

Uruchamiaj je z katalogu głównego repozytorium. Wymagają Ansible i PyYAML.

### Testowy odczyt sekretów

Poniższy stack wypisuje wszystkie sekrety, w tym `registry_htpasswd`, do logów.
Wolno używać go wyłącznie w środowisku testowym.

```bash
./06-docker-secrets.sh test apply
ssh ansible-test-swarm-manager \
  'docker stack deploy --compose-file - docker-secrets-test' \
  < inventories/test/docker-secrets-test/docker-compose.yml

ssh ansible-test-swarm-manager \
  'docker service logs --raw docker-secrets-test_secret-printer'
ssh ansible-test-swarm-manager 'docker stack rm docker-secrets-test'
```

PowerShell uruchomiony w katalogu `ansible`:

```powershell
wsl.exe -d Ubuntu -- ./06-docker-secrets.sh test apply

$composePath = (Resolve-Path `
    'inventories/test/docker-secrets-test/docker-compose.yml').Path

Push-Location '..\ansible-test'
try {
    Get-Content -Raw -Encoding utf8 $composePath |
        vagrant.exe ssh swarm-manager -c `
            'sudo docker stack deploy --compose-file - docker-secrets-test'

    vagrant.exe ssh swarm-manager -c `
        'sudo docker service logs --raw docker-secrets-test_secret-printer'
    vagrant.exe ssh swarm-manager -c `
        'sudo docker stack rm docker-secrets-test'
}
finally {
    Pop-Location
}
```

## Let's Encrypt i rotacja certyfikatów

`05-letsencrypt.sh` instaluje Certbot, skrypt w `/srv/cluster/bin` oraz timer
`cluster-certificate-renewal.timer`. Certbot przechowuje cały swój stan pod
`/srv/cluster/certificates/letsencrypt`; jedynymi plikami integracyjnymi poza
głównym katalogiem są unity systemd w `/etc/systemd/system`.

Przed uruchomieniem gatewaya można przetestować HTTP-01 przy pomocy
wbudowanego serwera Certbota. Port 80 musi być wolny i publicznie dostępny:

```bash
sudo /srv/cluster/bin/renew-certificates \
  --standalone --dry-run --force-renewal
```

Pierwszy rzeczywisty certyfikat można uzyskać tak samo bez działającego Nginx:

```bash
sudo /srv/cluster/bin/renew-certificates --standalone
```

Jeśli serwis `core_gateway` nie istnieje, skrypt sam wybiera tryb standalone.
Gdy gateway działa, domyślnie zapisuje token w
`/srv/cluster/www/gateway/letsencrypt`, który Nginx udostępnia na porcie 80.

Po udanym odnowieniu skrypt:

1. tworzy wersjonowane sekrety `gateway_tls_certificate_<hash>` i
   `gateway_tls_private_key_<hash>`;
2. atomowo aktualizuje
   `/srv/cluster/certificates/letsencrypt/current-secrets.env`;
3. aktualizuje działający `core_gateway` bez zatrzymywania pozostałych stacków;
4. usuwa poprzednie, nieużywane wersje sekretów.

`--dry-run` używa stagingowego CA i nie zmienia sekretów ani pliku env.

## Release i deployment

Gradle uruchomiony z katalogu głównego repozytorium tworzy manager-only
archive:

```bash
./gradlew clusterRelease
tar -tzf build/distributions/cluster-release.tar.gz
```

Workflow `.github/workflows/update_cluster.yml` przesyła archiwum wyłącznie na
managera. `apps/utils/update_cluster.sh` sprawdza SHA-256, bezpieczne ścieżki w
archiwum oraz wynik `docker stack config`, po czym instaluje release jako
`/srv/cluster/releases/<git-sha>` i atomowo przełącza `current`. Normalny deploy
nie wykonuje `stop_all`; `docker stack deploy --prune` uzgadnia stan usług.
Pierwsze wykonanie po migracji usuwa stare stacki `db`, `db_mysql` i dawny
stack aplikacji, a po zwolnieniu usuwa także starą sieć overlay. Poprzednie
release'y pozostają dostępne do ręcznego rollbacku.

Polecenia managera:

```bash
/srv/cluster/current/tools/start-all.sh
/srv/cluster/current/tools/start-stack.sh application
/srv/cluster/current/tools/stop-stack.sh application
/srv/cluster/current/tools/activate-release.sh <previous-release-id>
/srv/cluster/current/tools/set-image-tag.sh backend <image-tag>
/srv/cluster/current/tools/set-image-tag.sh banks <image-tag>
/srv/cluster/current/tools/set-image-tag.sh mcp <image-tag>
/srv/cluster/current/tools/set-image-tag.sh frontend <image-tag>
/srv/cluster/current/tools/set-image-tag.sh tapo <image-tag>
/srv/cluster/current/tools/restore-postgres.sh \
  postgres-YYYY-MM-DDTHH-MM-SSZ.tar.gz
/srv/cluster/current/tools/restore-postgres.sh \
  --database keycloak postgres-YYYY-MM-DDTHH-MM-SSZ.tar.gz
```

The first restore command replaces all databases and global objects from the
archive. Passing `--database <name>` replaces only that database and leaves
global roles untouched; the database owner role must already exist. Stop the
`application` stack before either restore operation.
The restore task runs on the manager, where the backup transfer job stores the
archives, and connects to PostgreSQL over the Swarm overlay network.

Tagi obrazów aplikacji są przechowywane na managerze w
`/srv/cluster/image-tags.env`, poza katalogami release'ów. Dzięki temu kolejne
`clusterRelease` zachowuje aktualnie wdrożone, niezmienne tagi zamiast
przywracać `latest`. Workflowy `deploy backend image` i `deploy banks image`
wymagają podania `image_tag`; zapisują go tym skryptem i uzgadniają stack
`application`. Workflow Reacta powinien analogicznie wywołać
`set-image-tag.sh frontend <image-tag>` i `start-stack.sh application`.
Obraz czytnika Tapo używa zmiennej `TAPO`; polecenie
`set-image-tag.sh tapo <image-tag>` zapisuje ją w tym samym pliku i wymaga
ponownego uzgodnienia stacka `application`.

Serwer MCP używa `MCP_IMAGE_TAG` i komponentu `mcp`.
[Pierwsze wdrożenie oraz zakres dostępu MCP](../docs/serwer-mcp.md).

## SSH pomiędzy hostami

Inventory `home` domyślnie czyta klucze z `~/.ssh/ansible-home`, a `test` z
`../ansible-test/.ssh`. Rola `base_host` kopiuje na każdy node wyłącznie jego
własny klucz prywatny, ustawia tryb `0600` i zarządza wpisem w `~/.ssh/config`.
Klucze publiczne pozostałych nodów muszą już znajdować się w
`authorized_keys`; dla środowiska testowego zapewnia to Vagrant.

W WSL klucze są tymczasowo kopiowane do prywatnego katalogu pod `/tmp`, aby
Ansible nie odrzucił ich z powodu uprawnień systemu plików Windows.

## Firewall

```bash
./04-firewall.sh test check
./04-firewall.sh test apply
./04-firewall.sh home apply
```

Inventory `home` ogranicza komunikację klastra i PostgreSQL do
`192.168.20.0/24`, a `test` do `192.168.56.0/24`. Porty `80` i `443` są
publiczne. Grafana jest dostępna pod `https://grafana.grzegorzewski.pl`.
Publiczny pull z registry jest dostępny pod
`https://public.registry.grzegorzewski.pl`, a prywatny registry z Basic Auth
dla pull i push pod `https://private.registry.grzegorzewski.pl`. Reguły UFW nie zastępują filtrowania ruchu publikowanego przez
Docker w łańcuchu `DOCKER-USER`.
