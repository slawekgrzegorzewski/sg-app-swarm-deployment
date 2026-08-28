# Backups downloader

Kontener pobiera z managera Swarma backupy PostgreSQL oraz Grafany do lokalnego
katalogu, weryfikuje każdą kopię przez SHA-256 i usuwa zdalny plik dopiero po
potwierdzeniu zgodności sum kontrolnych. Backup Grafany jest odczytywany przez
`sudo` na managerze, ponieważ katalog jest dostępny tylko dla roota.

Lokalny katalog może zawierać `.ssh` z kluczem prywatnym. Gdy logowanie hasłem
lub `sudo` go wymagają, dodaj plik `ssh_pass` z jednym hasłem. Plik nie jest
wypisywany w logach. Skrypt użyje klucza SSH, jeśli `ssh_pass` nie istnieje;
dla backupu Grafany w takim przypadku wymagany jest bezhasłowy `sudo`.

Przy pierwszym połączeniu downloader automatycznie zapisuje klucz hosta
managera w `known_hosts` w głównym katalogu backupu. Kolejne uruchomienia
akceptują tylko ten sam klucz; jego zmiana kończy połączenie błędem.

Uruchom polecenie z katalogu `tools/backups-downloader`. W PowerShellu ustaw
zmienną przed uruchomieniem Compose:

```powershell
$env:DEVELOPMENT_DIRECTORY = 'D:\OneDrive\Dokumenty\SG app backup'
docker compose up --build --abort-on-container-exit
```

W macOS/Linux:

```bash
export DEVELOPMENT_DIRECTORY="$HOME/backup"
docker compose up --build --abort-on-container-exit
```

`DEVELOPMENT_DIRECTORY` musi wskazywać istniejący lokalny katalog. Składnia
bind mountów w pliku Compose zachowuje poprawną interpretację ścieżek Windows,
w tym ścieżek z literą dysku, np. `D:\OneDrive\Dokumenty\SG app backup`.

Po zakończeniu pliki znajdą się w:

```text
POSTGRES/postgres-*.tar.gz
GRAFANA/grafana-*.db
```

Domyślny manager to `slawek@192.168.20.2`. Adres, użytkownika, port i katalog
źródłowy można zmienić przez zmienne `REMOTE_HOST`, `REMOTE_USER`,
`REMOTE_PORT` oraz `REMOTE_BACKUP_ROOT`. Synchronizacja bucketu S3 pozostaje
włączona dla zgodności z poprzednią wersją; aby ją pominąć, ustaw `SYNC_S3=false`.
