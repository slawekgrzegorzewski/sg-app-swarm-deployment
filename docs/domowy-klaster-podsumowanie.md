# Domowy klaster — aktualne podsumowanie infrastruktury, decyzji i otwartych tematów

## 1. Obecna infrastruktura fizyczna

### Sieć

Obecna topologia:

```text
                         STRYCH

                   światłowód Fiberlink
                           │
                           ▼
                     router HALNy
                           │
                           │ jeden kabel Ethernet
                           │ między strychem a domem
                           ▼

                          DOM

                 ASUS TUF Gaming AX5400
                  główny router ASUS
                           │
               ┌───────────┴───────────┐
               │                       │
              LAN                    AiMesh
               │                       │
               │                  ASUS RT-AX55
               │
          urządzenia LAN/Wi-Fi
```

Na strychu znajdują się również komputery klastra:

```text
STRYCH

HALNy
+
PC
+
Raspberry Pi 3
+
Raspberry Pi 4
+
Raspberry Pi 5
```

Obecnie cztery nody klastra korzystają z **Wi-Fi**.

Istotne ograniczenie fizyczne:

> Między strychem a miejscem, gdzie stoi TUF AX5400, istnieje tylko **jeden przewód Ethernet** i nie chcesz ciągnąć drugiego.

---

## 2. Plan przejścia klastra z Wi-Fi na Ethernet

### Decyzja

Zamiast kolejnego routera używamy **dwóch zarządzalnych switchy** oraz VLAN 802.1Q.

Wybrany model:

**TP-Link TL-SG108E**

Na razie zostajemy przy **1 Gb/s**, a nie 2.5 Gb/s.

Schemat:

```text
                         STRYCH

 Fiberlink HALNy
       │
       ▼
 ┌────────────────────────────┐
 │ TL-SG108E #1               │
 │                            │
 │ HALNy                      │
 │ PC                         │
 │ RPi3                       │
 │ RPi4                       │
 │ RPi5                       │
 │ trunk do domu              │
 └────────────┬───────────────┘
              │
              │ jeden istniejący kabel
              │
              ▼
 ┌────────────────────────────┐
 │ TL-SG108E #2               │
 │                            │
 │ trunk                      │
 │ TUF WAN                    │
 │ TUF LAN                    │
 └────────────┬───────────────┘
              │
              ▼
      ASUS TUF AX5400
```

---

## 3. VLAN-y

Potrzebujemy dwóch logicznych sieci na jednym przewodzie.

Przykładowo:

```text
VLAN 10 = WAN
VLAN 20 = LAN
```

Na strychu:

```text
TL-SG108E #1

HALNy       → VLAN 10 untagged
trunk       → VLAN 10 tagged
              VLAN 20 tagged

PC          → VLAN 20 untagged
RPi3        → VLAN 20 untagged
RPi4        → VLAN 20 untagged
RPi5        → VLAN 20 untagged
```

W domu:

```text
TL-SG108E #2

trunk       → VLAN 10 tagged
              VLAN 20 tagged

TUF WAN     → VLAN 10 untagged
TUF LAN     → VLAN 20 untagged
```

Dzięki temu jeden fizyczny kabel przenosi jednocześnie:

```text
HALNy
 ↓ WAN
TUF

oraz

TUF
 ↓ LAN
komputery na strychu
```

TUF nie musi wiedzieć o VLAN-ach. Dostaje normalny Ethernet na WAN i LAN.

---

## 4. Przepustowość tego rozwiązania

Same VLAN-y mają pomijalny narzut.

Ograniczeniem jest trunk:

```text
1 Gb/s full duplex
```

Ruch pomiędzy komputerami na strychu:

```text
PC ↔ RPi
RPi ↔ RPi
```

pozostaje na switchu strychowym i **nie przechodzi przez trunk do domu**.

To jest ważne dla:

- Docker Swarm,
- PostgreSQL,
- registry,
- kopiowania obrazów,
- backupów.

Internet do hosta na strychu przechodzi fizycznym trunkiem dwa razy:

```text
HALNy
 ↓
trunk → TUF WAN
 ↓
routing/NAT
 ↓
TUF LAN
 ↓
trunk → komputer
```

Ponieważ Ethernet jest full duplex, przy zwykłym downloadzie nadal możemy osiągnąć okolice pełnego gigabita.

Potencjalne ograniczenie pojawia się przy bardzo dużym jednoczesnym:

```text
download + upload
```

Na razie akceptujemy ten kompromis.

### Opcja na przyszłość

Jeżeli będzie potrzeba:

```text
TL-SG108E
      ↓
2.5G managed switches
```

i pozostawienie tej samej architektury VLAN.

Rozważaliśmy m.in. Grandstream GWN7721, ale **na razie zostajemy przy TL-SG108E**.

---

## 5. Okablowanie

Do krótkich połączeń potrzebujesz maksymalnie około:

```text
1–1,5 m
```

Rozważaliśmy Cat6 U/UTP, ale spodobała Ci się oferta:

**Unitek Cat.7 SSTP, płaski, 1 m z RTV Euro AGD**

Producent deklaruje miedziane żyły, więc nie jest to CCA.

W praktyce przy:

```text
1 m
+
1 Gb/s
```

ma ogromny zapas.

Płaska konstrukcja nie jest problemem na tak krótkim odcinku.

### Do kupienia

W przybliżeniu:

```text
STRYCH

HALNy → switch
PC    → switch
RPi3  → switch
RPi4  → switch
RPi5  → switch
```

oraz:

```text
DOM

switch → TUF WAN
switch → TUF LAN
```

czyli około **7 krótkich patchcordów**, jeśli istniejący kabel strych ↔ dom zostaje.

---

## 6. Rola ASUS TUF AX5400

TUF pozostaje głównym routerem.

Ma odpowiadać za:

```text
DHCP
NAT
firewall
Virtual Server / port forwarding
AiMesh
```

Nie chcemy dodawać kolejnego routera pomiędzy HALNy a TUF.

Powód:

```text
router
 ↓
router
 ↓
router
```

prowadziłby do kolejnych warstw NAT i komplikował port forwarding.

---

## 7. Virtual Server / port forwarding

To nadal realizuje TUF.

Przykładowo:

```text
WAN :443
   ↓
Swarm manager :443

WAN :10022
   ↓
PC :22

WAN :10023
   ↓
RPi3 :22
```

Switch i VLAN-y nie zmieniają tego modelu.

Każdy komputer nadal ma własny adres:

```text
192.168.52.x
```

w tej samej LAN.

---

## 8. Otwarta kwestia: HALNy

Trzeba kiedyś sprawdzić, czy HALNy działa jako:

```text
ONT / bridge
```

czy:

```text
router + NAT
```

Idealny wariant:

```text
Internet
 ↓
HALNy bridge/ONT
 ↓
publiczne IP
 ↓
TUF WAN
 ↓
NAT
 ↓
192.168.52.0/24
```

Jeżeli HALNy również robi NAT:

```text
HALNy NAT
 ↓
TUF NAT
```

masz double NAT.

To jest rzecz do zweryfikowania.

---

## 9. Ogólna koncepcja klastra

Główna zasada, do której doszliśmy:

> **Host powinien być możliwie prosty: Linux + Docker + filesystem. Wszystko, co się da, działa jako Docker Swarm service.**

Czyli:

```text
Linux
  │
Docker Engine
  │
Docker Swarm
  │
  ├── aplikacje
  ├── PostgreSQL
  ├── registry
  ├── GitHub Runner
  ├── CloudWatch Agent
  ├── reverse proxy
  └── inne usługi
```

---

## 10. Docker Swarm

Klaster składa się obecnie z czterech maszyn:

```text
PC
Raspberry Pi 3
Raspberry Pi 4
Raspberry Pi 5
```

Jest więc mieszany architektonicznie:

```text
PC         → amd64/x86-64
Raspberry  → ARM
```

Trzeba to brać pod uwagę przy Docker images.

---

## 11. Infrastructure as Code

### Decyzja

Do automatycznego przygotowania hostów chcemy użyć **Ansible**.

Ansible jest darmowy/open-source.

Ma odpowiadać za:

```text
Linux
├── hostname
├── użytkowników
├── SSH
├── pakiety
├── Docker
├── Docker config
├── katalogi /srv
├── mounty
├── firewall
├── Swarm init/join
└── node labels
```

Docelowy scenariusz:

```text
czysty Linux
     ↓
SSH
     ↓
Ansible
     ↓
Docker
     ↓
Docker Swarm
     ↓
stack deploy
     ↓
gotowy klaster
```

Docelowo np.:

```bash
make cluster
```

---

## 12. Podział odpowiedzialności

Chcemy mieć wyraźnie:

```text
ANSIBLE
   ↓
konfiguruje HOSTY
```

a:

```text
DOCKER SWARM
   ↓
konfiguruje USŁUGI
```

Czyli Ansible nie powinien bez potrzeby instalować bezpośrednio:

```text
PostgreSQL
CloudWatch Agent
GitHub Runner
registry
```

jako systemd services.

One mają być kontenerami Swarma.

---

## 13. Node labels

Usługi wymagające konkretnego hosta przypinamy labelami.

Np.:

```bash
docker node update --label-add postgres=true pc
docker node update --label-add registry=true rpi5
docker node update --label-add builder=true pc
```

i:

```yaml
deploy:
  placement:
    constraints:
      - node.labels.postgres == true
```

---

## 14. PostgreSQL

### Decyzja początkowa

PostgreSQL działa w Swarmie jako:

```text
replicas: 1
```

i jest przypięty do konkretnego node'a z odpowiednim storage.

Nie robimy:

```text
replicas: 3
```

w nadziei, że Swarm sam zapewni HA.

Swarm nie rozumie:

```text
Postgres primary
Postgres standby
replication
failover
split brain
```

---

## 15. PostgreSQL HA — opcja późniejsza

Jeżeli kiedyś będzie potrzeba:

```text
Postgres PRIMARY
       │
       │ streaming replication
       ▼
Postgres STANDBY
```

plus np.:

```text
Patroni
+
etcd/Consul
```

Na obecnym etapie uznaliśmy to raczej za niepotrzebną złożoność.

---

## 16. PostgreSQL — storage

Dane powinny być na trwałym filesystemie hosta, np.:

```text
/srv/postgres
```

a nie być zależne od przypadkowego ephemeral storage kontenera.

Usługa Postgresa jest przypisana do node'a, na którym znajduje się ten storage.

---

## 17. PostgreSQL — backup

Pierwsza warstwa:

```text
codzienny pg_dump -Fc
+
pg_dumpall --globals-only
```

np.:

```text
/srv/backups/postgres
```

Lokalna retencja:

```text
~14 dni
```

Ale backup nie może istnieć wyłącznie na tym samym komputerze.

Druga kopia:

```text
Postgres node
    │
    │ rsync/SSH
    ▼
inny fizyczny node/dysk
```

---

## 18. PostgreSQL — PITR

Opcja późniejsza:

```text
base backup
+
WAL archiving
```

czyli **Point-In-Time Recovery**.

Pozwala np. przywrócić:

```text
2026-08-17 13:42:17
```

a nie tylko ostatni nocny dump.

---

## 19. Zot zamiast Amazon ECR

Obrazy Docker są przechowywane we własnym klastrze, zamiast w Amazon ECR.

Jako registry wybrany został **zot** (`ghcr.io/project-zot/zot`). Działa jako
kompatybilny z Docker Registry v2 serwer OCI, z włączonym trybem `docker2s2`,
wyszukiwaniem, UI oraz wbudowanym garbage collection.

Storage registry jest trwały:

```text
$PERMANENT_DATA_DIR/registry/data
```

W konfiguracji zot garbage collection uruchamia się automatycznie. Nie należy
używać starego polecenia `registry garbage-collect`, które dotyczyło obrazu
Docker Distribution.

---

## 20. Zot jako Swarm service

Zot działa jako pojedyncza usługa Swarma przypięta do node'a przeznaczonego na
registry.

Np.:

```text
registry.grzegorzewski.pl
```

Przypisany do konkretnego node'a:

```yaml
placement:
  constraints:
    - node.labels.registry == true
```

Konfiguracja usługi znajduje się w:

```text
apps/core/stack/config/zot-config.json
```

Dane są montowane do `/var/lib/registry`, a usługa nasłuchuje na porcie 5000
w sieci Swarma. HTTPS i Basic Auth pozostają obsługiwane przez istniejący
Nginx reverse proxy pod adresem:

```text
https://grzegorzewski.pl:5005
```

Interfejs webowy Zot jest dostępny pod adresem
`https://grzegorzewski.pl:5005/` i jest chroniony przez ten sam Basic Auth co
Docker Registry API.

Docker clients nadal używają tego samego adresu registry, więc zmiana z
Distribution Registry na zot nie wymaga zmiany pipeline'ów.

---

## 21. GitHub self-hosted Runner

To jeden z ciekawszych pomysłów, które pojawiły się w rozmowie.

Docelowy pipeline:

```text
git push
   ↓
GitHub
   ↓
GitHub Actions
   ↓
self-hosted runner w domu
   ↓
test
   ↓
build
   ↓
Docker build
   ↓
local registry
   ↓
Docker Swarm deploy
```

---

## 22. Runner również jako Swarm service

Pierwotnie rozważaliśmy systemd na hoście, ale po ustaleniu zasady:

> wszystkie kontenery mają być w Swarmie

zmieniliśmy kierunek.

Runner ma również działać jako:

```text
Docker Swarm service
```

najprawdopodobniej przypięty do managera/build node'a.

---

## 23. Runner → Docker

Najprostszy wariant:

```text
/var/run/docker.sock
```

zamontowany do runnera.

Dzięki temu workflow może robić:

```bash
docker build
docker push
docker service update
docker stack deploy
```

### Ryzyko

Docker socket daje runnerowi praktycznie pełną kontrolę nad hostem.

Dlatego:

- tylko prywatne/zaufane repozytoria,
- nie wykonywać niezaufanych PR,
- uważać z sekretami.

---

## 24. BuildKit — opcja późniejsza

Można jeszcze bardziej konsekwentnie potraktować zasadę „wszystko w Swarmie”:

```text
github-runner
     │
     ▼
BuildKit Swarm service
     │
     ▼
registry
```

Runner używa Dockera managera głównie do deploymentu.

Na razie do rozpatrzenia.

---

## 25. Multi-architecture Docker images

Ponieważ:

```text
PC  → amd64
RPi → arm64
```

warto budować obrazy:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  ...
```

Jeden tag:

```text
registry.grzegorzewski.pl/banks:<version>
```

może wtedy działać na obu architekturach.

---

## 26. GitHub Actions storage

Self-hosted runner zmniejsza wykorzystanie infrastruktury GitHuba, ale:

```text
actions/upload-artifact
actions/cache
```

mogą nadal używać storage GitHuba.

Preferowany pipeline:

```text
Gradle build
    ↓
Docker build
    ↓
lokalny registry
```

bez zbędnego `upload-artifact`.

---

## 27. CloudWatch Agent

Interesują Cię **tylko logi aplikacji**, nie metryki hosta.

Dlatego agent nie potrzebuje:

```text
/proc
/sys
Docker socket
```

Potrzebuje jedynie dostępu do katalogów logów.

---

## 28. CloudWatch Agent jako Swarm global service

Chcemy:

```yaml
deploy:
  mode: global
```

czyli:

```text
każdy node
   ↓
jeden CloudWatch Agent
```

Gdy do Swarma dojdzie kolejny host, automatycznie dostanie agenta.

---

## 29. Lokalizacja logów

Preferowany standard:

```text
/srv/logs/
├── banks/
├── frontend/
├── service-a/
└── ...
```

Aplikacja:

```yaml
volumes:
  - /srv/logs/banks:/app/logs
```

CloudWatch Agent:

```yaml
volumes:
  - /srv/logs:/logs:ro
```

To preferujemy nad named volume dla logów.

---

## 30. Migracja kontenera między node'ami

Jeżeli `banks` działał na:

```text
RPi5
```

i Swarm przeniesie go na:

```text
PC
```

powstaną potencjalnie:

```text
RPi5:/srv/logs/banks/
PC:/srv/logs/banks/
```

To jest akceptowalne.

Stary agent widzi stary plik, ale nikt już do niego nie dopisuje.

Nowy agent obsługuje nowe wpisy.

---

## 31. CloudWatch Log Streams

Nie chcemy jednego wspólnego:

```text
banks
```

dla wszystkich hostów.

Preferujemy:

```text
banks-{local_hostname}
```

np.:

```text
/home-cluster/banks

banks-rpi3
banks-rpi4
banks-rpi5
banks-pc
```

Jedna Log Group, wiele streamów.

---

## 32. Stan CloudWatch Agenta

Agent musi pamiętać offset pliku.

Stan powinien przeżyć restart kontenera.

Np.:

```text
/srv/cloudwatch/state
```

Czyli:

```text
/srv/
├── logs/
└── cloudwatch/
    └── state/
```

---

## 33. Rotacja logów

Preferowany mechanizm:

```text
rename + create
```

czyli:

```text
log.txt
 ↓
log.1.txt

nowy log.txt
```

Agent może wtedy:

```text
doczytać log.1.txt do EOF
+
zacząć nowy log.txt
```

---

## 34. Czego nie chcemy przy rotacji

Unikamy:

```text
copytruncate
```

bo istnieje race condition:

```text
copy
 ↓
logger dopisuje wpis
 ↓
truncate
```

i wpis może zginąć.

---

## 35. CloudWatch Agent i rotowane pliki

Agent powinien widzieć również rotowane pliki, np.:

```text
/logs/banks/log*.txt
```

czyli:

```text
log.txt
log.1.txt
log.2.txt
```

---

## 36. Test niezawodności logów

Przed uznaniem konfiguracji za poprawną chcemy zrobić test:

```text
1
2
3
...
100000
```

wygenerowanych wpisów.

W czasie testu:

- agresywna rotacja,
- restart CloudWatch Agenta,
- restart aplikacji,
- reschedule Swarma,
- migracja node A → node B,
- później node B → node A.

Na końcu CloudWatch:

```text
100000 wpisów
100000 unikalnych numerów
0 brakujących
0 duplikatów
```

---

## 37. UPS

UPS **nie musi mieć LAN**.

Preferowany model:

```text
UPS
 │
 ├── zasilanie → switch
 ├── zasilanie → RPi
 ├── zasilanie → PC
 │
 └── USB → jeden node
             │
             ▼
            NUT
             │
             └── LAN → pozostałe nody
```

Jeden host komunikuje się z UPS przez USB, a pozostali klienci NUT przez sieć.

---

## 38. UPS i automatyczne wyłączanie

Docelowo:

```text
zanik 230 V
   ↓
UPS
   ↓
NUT wykrywa pracę na baterii
   ↓
po ustalonym czasie/poziomie baterii
   ↓
bezpieczne shutdowny
```

Istotne szczególnie dla PostgreSQL.

---

## 39. Co może być pod UPS-em

Do rozstrzygnięcia dokładny zakres, ale sensownie:

```text
switch na strychu
Raspberry Pi
PC / wybrane nody
ewentualnie HALNy
```

Jeżeli router TUF znajduje się fizycznie w innym miejscu, może wymagać osobnego UPS-a albo innego rozwiązania zasilania.

---

## 40. Docelowa wizja całego środowiska

```text
                         INTERNET
                            │
                            ▼
                         HALNy
                            │
                     VLAN WAN 10
                            │
                ┌───────────┴───────────┐
                │ TL-SG108E STRYCH      │
                │                       │
                │ PC                    │
                │ RPi3                  │
                │ RPi4                  │
                │ RPi5                  │
                └───────────┬───────────┘
                            │
                    VLAN 10 + VLAN 20
                       jeden kabel
                            │
                ┌───────────▼───────────┐
                │ TL-SG108E DOM         │
                └───────┬────────┬──────┘
                        │        │
                      WAN        LAN
                        │        │
                    ┌───▼────────▼───┐
                    │ TUF AX5400     │
                    │ DHCP / NAT     │
                    │ firewall       │
                    │ port forwarding│
                    │ AiMesh         │
                    └───────┬────────┘
                            │
                         RT-AX55
                           Mesh
```

Na każdym nodzie:

```text
Linux
 │
Docker
 │
Docker Swarm
 │
 ├── app
 ├── infrastructure services
 └── CloudWatch Agent

/srv/
├── logs
├── cloudwatch
├── postgres        [tylko DB node]
├── registry        [tylko registry node]
└── backups
```

A ponad tym:

```text
Ansible
   ↓
odtwarza hosty i Swarm
```

oraz:

```text
GitHub
   ↓
self-hosted runner
   ↓
build
   ↓
local registry
   ↓
Docker Swarm
```

---

## 41. Najważniejsze rzeczy nadal do zdecydowania

W kolejności, w której warto je zamykać:

1. **Kupić i skonfigurować 2× TL-SG108E.**
2. Ustalić dokładne porty/PVID dla VLAN 10 i VLAN 20.
3. Sprawdzić kategorię istniejącego kabla strych ↔ dom.
4. Sprawdzić, czy HALNy działa jako bridge/ONT czy router/NAT.
5. Ustalić statyczne DHCP/IP wszystkich czterech node'ów.
6. Wybrać dokładną topologię Swarma: manager/worker.
7. Zdecydować, czy na razie jeden manager wystarcza.
8. Zaprojektować Ansible inventory i role.
9. Ustalić strukturę `/srv`.
10. Zot został wybrany zamiast `registry:3`.
11. Wybrać reverse proxy.
12. Zaprojektować self-hosted GitHub Runner.
13. Zdecydować Docker socket vs osobny BuildKit.
14. Ustalić strategię tagowania Docker images.
15. Przypisać PostgreSQL do konkretnego node'a/storage.
16. Przygotować codzienny backup PostgreSQL.
17. Wybrać drugi fizyczny cel dla backupów.
18. Zdecydować, kiedy wdrażać PITR.
19. Skonteneryzować CloudWatch Agent jako global service.
20. Ustandaryzować Logback/log rotation.
21. Przetestować CloudWatch + rotację + migrację między node'ami.
22. Wybrać UPS zgodny z NUT/USB.
23. Zaprojektować kolejność shutdownów po zaniku zasilania.
24. Na końcu zrobić **pełny disaster-recovery test**: czysty Linux → Ansible → Swarm → restore danych → działające aplikacje.

---

## Nadrzędna zasada architektoniczna

> **Ansible odtwarza maszyny, Swarm odtwarza usługi, a trwałe dane są jawnie wydzielone do `/srv` i backupowane poza node, na którym powstają.**
> **Dokument historyczny.** Opisuje układ sprzed migracji do
> `/srv/cluster`. Aktualne ścieżki, grupy inventory i procedury znajdują się w
> [`ansible/README.md`](../ansible/README.md).
