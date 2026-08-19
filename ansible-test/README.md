# Vagrant — środowisko testowe Docker Swarm

Środowisko składa się z czterech maszyn Ubuntu:

| Maszyna | Prywatny adres IP |
|---|---:|
| `swarm-manager` | `192.168.56.10` |
| `swarm-worker-1` | `192.168.56.11` |
| `swarm-worker-2` | `192.168.56.12` |
| `swarm-worker-3` | `192.168.56.13` |

Każda maszyna ma również interfejs `public_network` z adresem pobieranym z DHCP lokalnego routera.

Wszystkie komendy uruchamiaj z katalogu `ansible-test`:

```powershell
cd D:\Development\Projects\sg-app-swarm-deployment\ansible-test
```

## Walidacja i status

```powershell
# Sprawdzenie składni Vagrantfile
vagrant validate

# Status wszystkich maszyn w bieżącym środowisku
vagrant status

# Status wszystkich środowisk Vagranta na hoście
vagrant global-status

# Wersja Vagranta
vagrant version
```

## Tworzenie i uruchamianie maszyn

```powershell
# Utworzenie i uruchomienie wszystkich nodów
vagrant up

# Utworzenie/uruchomienie jednego noda
vagrant up swarm-manager
vagrant up swarm-worker-1
vagrant up swarm-worker-2
vagrant up swarm-worker-3

# Uruchomienie bez wykonywania provisioningu
vagrant up --no-provision

# Uruchomienie z provisioningiem
vagrant up --provision
```

Przy pierwszym `vagrant up` Vagrant może zapytać, którą kartę sieciową hosta wykorzystać dla `public_network`.

## Provisioning

Provisioning instaluje `python3`, tworzy użytkownika `slawek`, dodaje klucz SSH i konfiguruje `sudo` bez hasła.

```powershell
# Provisioning wszystkich nodów
vagrant provision

# Provisioning jednego noda
vagrant provision swarm-worker-3

# Ponowne uruchomienie z provisioningiem
vagrant reload --provision
vagrant reload swarm-worker-3 --provision
```

Na już utworzonych maszynach zmiany w `Vagrantfile` wymagają zwykle:

```powershell
vagrant provision
```

## Połączenie SSH

### Przez Vagranta

```powershell
# Połączenie z domyślnym użytkownikiem Vagranta
vagrant ssh swarm-manager

# Połączenie z konkretnym nodem i wykonanie komendy
vagrant ssh swarm-worker-3 -c "hostname && ip -br addr"

# Wygenerowanie konfiguracji SSH
vagrant ssh-config
vagrant ssh-config swarm-worker-3
```

### Jako użytkownik `slawek`

Wspólna para kluczy znajduje się w:

```text
ansible-test/.ssh/slawek_vagrant_ed25519
ansible-test/.ssh/slawek_vagrant_ed25519.pub
```

Adres LAN trzeba sprawdzić poleceniem `ip -br addr` — jest przydzielany przez DHCP:

```powershell
vagrant ssh swarm-manager -c "ip -br addr"

ssh -i .\.ssh\slawek_vagrant_ed25519 slawek@<ADRES_LAN_NODA>
```

Przykład dla sieci prywatnej Vagranta:

```powershell
ssh -i .\.ssh\slawek_vagrant_ed25519 slawek@192.168.56.10
```

## Sieć i porty

```powershell
# Lista przekierowanych portów
vagrant port
vagrant port swarm-manager

# Adresy interfejsów sieciowych noda
vagrant ssh swarm-manager -c "ip -br addr"
```

`private_network` (`192.168.56.x`) służy do komunikacji host ↔ VM oraz VM ↔ VM. `public_network` otrzymuje adres z lokalnego DHCP i może być dostępny dla innych urządzeń w LAN-ie.

## Zatrzymywanie i wznawianie

```powershell
# Łagodne zatrzymanie wszystkich maszyn
vagrant halt

# Zatrzymanie jednego noda
vagrant halt swarm-worker-3

# Wstrzymanie stanu maszyn
vagrant suspend
vagrant suspend swarm-worker-3

# Wznowienie maszyn po suspend
vagrant resume
vagrant resume swarm-worker-3

# Restart maszyn i ponowne odczytanie konfiguracji sieci
vagrant reload
vagrant reload swarm-worker-3

# Restart bez provisioningu
vagrant reload --no-provision
```

## Snapshoty

Snapshot `fresh` najlepiej utworzyć po pierwszym pełnym `vagrant up`, przed zmianami wykonywanymi podczas testów:

```powershell
# Snapshot całego środowiska
vagrant snapshot save fresh

# Lista snapshotów
vagrant snapshot list

# Przywrócenie świeżego stanu bez ponownego provisioningu
vagrant snapshot restore --no-provision fresh

# Usunięcie snapshotu
vagrant snapshot delete fresh

# Zastąpienie snapshotu aktualnym stanem
vagrant snapshot save -f fresh
```

Snapshot pojedynczego noda:

```powershell
vagrant snapshot save swarm-worker-3 worker-3-clean
vagrant snapshot list swarm-worker-3
vagrant snapshot restore --no-provision swarm-worker-3 worker-3-clean
vagrant snapshot delete swarm-worker-3 worker-3-clean
```

Operacje stosu snapshotów:

```powershell
vagrant snapshot push
vagrant snapshot pop
```

## Usuwanie maszyn

```powershell
# Usunięcie jednego noda — wymaga ponownego vagrant up
vagrant destroy swarm-worker-3

# Wymuszenie usunięcia jednego noda bez pytania
vagrant destroy -f swarm-worker-3

# Usunięcie całego środowiska — operacja destrukcyjna
vagrant destroy

# Wymuszenie usunięcia całego środowiska
vagrant destroy -f
```

Usunięcie VM może również usunąć lokalne snapshoty powiązane z tą maszyną.

## Boxy Vagranta

```powershell
# Lista pobranych boxów
vagrant box list

# Sprawdzenie dostępności aktualizacji boxów
vagrant box outdated

# Aktualizacja używanego boxa
vagrant box update

# Usunięcie konkretnej wersji boxa
vagrant box remove ubuntu/jammy64

# Spakowanie środowiska do pliku box
vagrant package --output ansible-test.box
```

## Przydatne informacje diagnostyczne

```powershell
# Szczegółowy status konkretnej maszyny
vagrant status swarm-manager

# Konfiguracja SSH dla konkretnej maszyny
vagrant ssh-config swarm-manager

# Logowanie z rozszerzonym debugowaniem
vagrant up --debug
vagrant ssh swarm-manager --debug
```

## Typowy cykl pracy

```powershell
# Pierwsze uruchomienie
vagrant validate
vagrant up
vagrant snapshot save fresh

# Po wykonaniu testów szybki reset
vagrant snapshot restore --no-provision fresh

# Dodanie lub odtworzenie konkretnego noda
vagrant up swarm-worker-3
vagrant provision swarm-worker-3
```
