# Plan rozwoju Ansible

## Stan obecny

- Wspólny playbook `playbooks/bootstrap-hosts.yml` przygotowuje hosty Debianowe.
- Dostępne są inventory `home` i `test`.
- Oba inventory używają tych samych logicznych nazw hostów: `PC2`, `rpi5`, `rpi4`, `rpi3`.
- Inventory testowe używa nazw DNS VM jako `ansible_host`.
- Skrypt `bootstrap.sh` obsługuje tryby `check` i `apply`, wybór środowiska oraz limit hostów.
- Rola `base_host` instaluje pakiety bazowe, ustawia hostname, strefę czasową, grupę sudo i katalogi.

## Kolejne prace

### 1. Uporządkowanie inventory i grup funkcjonalnych

Status: wykonane.

Dodano wspólne grupy funkcjonalne w `home` i `test`:

- `swarm_managers` — `PC2`;
- `swarm_workers` — `rpi5`, `rpi4`, `rpi3`;
- `postgres_nodes`;
- `registry_nodes`;
- `builder_nodes`.

Role i playbooki używają tych grup zamiast nazw konkretnych maszyn.

### 2. Weryfikacja idempotencji

Status: wykonane.

Na środowisku testowym wykonano dwukrotny `apply` oraz `check`; druga próba nie wykazała nowych zmian.

Powtórzenie testu:

```bash
./bootstrap.sh test apply
./bootstrap.sh test apply
./bootstrap.sh test check
```

Drugie `apply` powinno zakończyć się bez nowych zmian, a wszystkie hosty powinny mieć `failed=0` i `unreachable=0`.

### 3. Rozdzielenie katalogów `/srv` według funkcji hosta

Wspólne katalogi pozostawić w `base_host`. Katalogi specjalistyczne przenieść do zmiennych grupowych lub osobnych ról:

- `postgres_nodes` — `/srv/postgres`, `/srv/postgres-hot-standby`;
- `registry_nodes` — `/srv/registry`, `/srv/registry/data`;
- hosty aplikacyjne — właściwe katalogi logów i danych.

### 4. Rola `docker_engine`

Rola powinna:

- dodać oficjalne repozytorium Dockera;
- zainstalować Docker Engine, CLI, containerd, Buildx i Compose;
- dodać `cluster_admin_user` do grupy `docker`;
- zarządzać `/etc/docker/daemon.json`;
- włączyć i uruchomić Docker oraz containerd;
- restartować usługi tylko po zmianie konfiguracji.

Konfigurację rejestru i inne ustawienia Dockera trzymać w zmiennych inventory, a nie w zadaniach zapisanych na stałe.

### 5. Rola `docker_swarm`

Rola powinna:

- inicjalizować Swarm na `swarm_managers`;
- pobierać token workera z managera;
- dołączać hosty z `swarm_workers`;
- być bezpieczna przy ponownym uruchomieniu;
- używać jawnego `swarm_advertise_addr`.

Operacje opuszczenia lub wymuszonego resetu Swarma powinny być osobnym, świadomie uruchamianym playbookiem.

### 6. Etykiety nodów Swarma

Ustawić z managera etykiety używane przez stacki, np.:

- `postgres=true`;
- `registry=true`;
- `builder=true`.

Etykiety powinny wynikać z grup inventory i odpowiadać constraintom w plikach Compose.

### 7. Firewall

Po uruchomieniu Swarma dodać rolę firewall z regułami dla:

- SSH `22/tcp`;
- managera Swarma `2377/tcp`;
- komunikacji nodów `7946/tcp` i `7946/udp`;
- overlay network `4789/udp`;
- wymaganych portów aplikacyjnych.

Ruch Swarma ograniczyć do sieci klastra/VLAN-u.

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
