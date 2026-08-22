# Plan rozwoju Ansible

## Stan obecny

- Wspólny playbook `playbooks/bootstrap-hosts.yml` przygotowuje hosty Debianowe i Ubuntu z Docker Engine.
- Dostępne są inventory `home` i `test`.
- Oba inventory używają tych samych logicznych nazw hostów: `PC2`, `rpi5`, `rpi4`, `rpi3`.
- Inventory testowe używa nazw DNS VM jako `ansible_host`.
- Skrypt `01-bootstrap.sh` obsługuje tryby `check` i `apply`, wybór środowiska oraz limit hostów.
- Role `base_host` i `docker_engine` przygotowują pakiety bazowe, hostname, strefę czasową, grupy użytkownika, katalogi i Docker Engine.

## Kolejne prace

### 1. Uporządkowanie inventory i grup funkcjonalnych

Status: wykonane.

Dodano wspólne grupy funkcjonalne w `home` i `test`:

- `swarm_managers` — `PC2`;
- `swarm_workers` — `rpi5`, `rpi4`, `rpi3`;
- `postgres_nodes`;
- `registry_nodes`.

Role i playbooki używają tych grup zamiast nazw konkretnych maszyn.

### 2. Weryfikacja idempotencji

Status: wykonane.

Na środowisku testowym wykonano dwukrotny `apply` oraz `check`; druga próba nie wykazała nowych zmian.

Powtórzenie testu:

```bash
./01-bootstrap.sh test apply
./01-bootstrap.sh test apply
./01-bootstrap.sh test check
```

Drugie `apply` powinno zakończyć się bez nowych zmian, a wszystkie hosty powinny mieć `failed=0` i `unreachable=0`.

### 3. Rozdzielenie katalogów `/srv` według funkcji hosta

Status: wykonane.

Wspólne katalogi pozostawić w `base_host`. Katalogi specjalistyczne przenieść do zmiennych grupowych lub osobnych ról:

- `postgres_nodes` — `/srv/postgres`, `/srv/postgres-hot-standby`;
- `registry_nodes` — `/srv/registry`, `/srv/registry/data`;
- hosty aplikacyjne — właściwe katalogi logów i danych.

### 4. Rola `docker_engine`

Status: wykonane.

Rola:

- dodać oficjalne repozytorium Dockera;
- zainstalować Docker Engine, CLI, containerd, Buildx i Compose;
- dodać `cluster_admin_user` do grupy `docker`;
- włączyć i uruchomić Docker oraz containerd;
- nie restartuje usług bez zmiany ich konfiguracji.

Registry jest dostępne przez HTTPS, dlatego `/etc/docker/daemon.json` nie jest
potrzebny i rola go nie tworzy, o ile certyfikat jest zaufany przez hosta. W
razie prywatnego CA należy dodać jego certyfikat do systemowego magazynu
zaufanych certyfikatów, a nie konfigurować `insecure-registries`.

### 5. Rola `docker_swarm`

Status: wykonane.

Rola [docker_swarm](/Users/slawekgrzegorzewski/Development/Slawek/sg-app-swarm-deployment/ansible/roles/docker_swarm) oraz playbooki `docker-swarm.yml` i `docker-swarm-reset.yml`:

- inicjalizować Swarm na `swarm_managers`;
- pobierać token workera z managera;
- dołączać hosty z `swarm_workers`;
- być bezpieczna przy ponownym uruchomieniu;
- używają jawnego `docker_swarm_advertise_addr`.

Operacje opuszczenia lub wymuszonego resetu Swarma są osobnym, świadomie uruchamianym playbookiem `docker-swarm-reset.yml`.

### 6. Etykiety nodów Swarma

Ustawić z managera etykiety używane przez stacki, np.:

- `postgres=true`;
- `registry=true`;

Etykiety powinny wynikać z grup inventory i odpowiadać constraintom w plikach Compose.
Etykieta `builder` została odłożona razem z funkcją builder nodes.

Status: zaimplementowane w roli `docker_swarm_labels` i playbooku
`playbooks/docker-swarm-labels.yml`, uruchamianym przez `03-docker-swarm-labels.sh`.

### 7. Firewall

Po uruchomieniu Swarma dodać rolę firewall z regułami dla:

- SSH `22/tcp`;
- managera Swarma `2377/tcp`;
- komunikacji nodów `7946/tcp` i `7946/udp`;
- overlay network `4789/udp`;
- wymaganych portów aplikacyjnych.

Ruch Swarma ograniczyć do sieci klastra `192.168.20.0/24` w środowisku home.
Środowisko testowe używa `192.168.56.0/24`.

Status: zaimplementowane w roli `firewall` i playbooku `playbooks/firewall.yml`,
uruchamianym przez `04-firewall.sh`. Porty `80/tcp`, `443/tcp` i `5005/tcp`
są dostępne zewnętrznie, a `5432/tcp` tylko z sieci klastra.

### 8. Oddzielenie provisioning od deploymentu

Ansible powinien przygotowywać hosty, Dockera i Swarma. Wdrażanie stacków powinno być osobnym etapem, uruchamianym jawnie po przygotowaniu infrastruktury.

### 9. Sekrety

Nie przechowywać haseł, tokenów ani kluczy w inventory ani w repozytorium. Dodać Ansible Vault lub inną kontrolowaną integrację z menedżerem sekretów.

### 10. Automatyczna walidacja

Dodać do lokalnego/CI workflow:

```bash
ansible-playbook --syntax-check
ansible-lint
yamllint
```

Minimalny test integracyjny powinien odtwarzać snapshot Vagranta, wykonywać `apply` dwukrotnie i sprawdzać stan Swarma przez `docker node ls`.

## Zalecana kolejność

1. Dokończyć grupy funkcjonalne inventory.
2. Zweryfikować idempotencję `base_host`.
3. Rozdzielić katalogi `/srv` według grup.
4. Zaimplementować `docker_engine`.
5. Zaimplementować `docker_swarm`.
6. Dodać etykiety nodów.
7. Dodać firewall.
8. Dopiero potem automatyzować deployment stacków i obsługę sekretów.
