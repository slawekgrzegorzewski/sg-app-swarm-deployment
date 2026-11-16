# Vaultwarden

Usługa `application_vaultwarden` udostępnia sejf pod
`https://vault.grzegorzewski.pl`. Klienci Bitwarden powinni używać tego adresu
jako serwera własnego. Publiczna rejestracja jest wyłączona; administrator
zaprasza użytkowników przez `/admin`. Poczta korzysta z istniejącego konta
Brevo oraz sekretu `brevo_smtp_password` przez STARTTLS.

Jedna replika zapisuje SQLite, załączniki i klucze w
`/srv/cluster/data/vaultwarden`. Grupa inventory `vaultwarden_nodes` wskazuje
dokładnie jednego managera, obecnie PC2. Ansible nadaje mu etykietę
`workload.vaultwarden` oraz tworzy katalog danych dla UID/GID 1000 z prawami
0700. Aktualizacje zatrzymują poprzednią replikę przed uruchomieniem nowej,
aby dwa procesy serwera nie korzystały równocześnie z tego katalogu.
Przeniesienie grupy na inny host wymaga osobnego przeniesienia danych.

## Pierwsze wdrożenie

1. Dodaj rekord DNS A `vault.grzegorzewski.pl` wskazujący publiczny adres
   gatewaya. Jeśli dodajesz AAAA, IPv6 również musi prowadzić do tego gatewaya.
2. Wygeneruj silny token administratora i zachowaj go w bezpiecznym miejscu
   dostępnym również przed uruchomieniem Vaultwarden.
   Jego hash Argon2id można wygenerować interaktywnie:

   ```bash
   docker run --rm -it vaultwarden/server:1.37.5 /vaultwarden hash
   ```

   Zapisz sam hash `$argon2id$...`, bez `ADMIN_TOKEN=`, cudzysłowów ani
   podwajania znaków `$`, jako sekret Docker Swarm. W sesji Bash na managerze
   wykonaj poniższe polecenia i wklej hash do ukrytego promptu:

   ```bash
   IFS= read -r -s -p 'Hash Argon2id tokena administratora: ' vaultwarden_admin_hash
   printf '\n'
   if [[ "$vaultwarden_admin_hash" == '$argon2id$'* ]]; then
       printf '%s' "$vaultwarden_admin_hash" | docker secret create vaultwarden_admin_token -
   else
       printf 'Niepoprawny hash. Sekret nie został utworzony.\n' >&2
   fi
   unset vaultwarden_admin_hash
   ```

   Wklejona wartość nie trafia do historii poleceń ani argumentów procesu
   Dockera. Polecenie tworzy nowy sekret; nie nadpisuje istniejącego.
   Do panelu logujesz się oryginalnym tokenem, a Docker otrzymuje hash przez
   plik sekretu. `vaultwarden_admin_token` jest zarządzany ręcznie, poza listą
   synchronizowaną z Bitwarden. Uruchomienie Vaultwarden nie wymaga dodawania
   ani odczytywania danych w Bitwarden CLI.
3. Przed pushem na `main` wykonaj z katalogu repozytorium provisioning:

   ```bash
   ./ansible/01-bootstrap.sh home apply
   ./ansible/03-docker-swarm-labels.sh home apply
   ./ansible/05-letsencrypt.sh home apply
   ```

   Wymagania SSH opisuje [instrukcja Ansible](../ansible/README.md).
   Te polecenia przygotowują katalogi, etykiety i odnowienie certyfikatu;
   samo `05-letsencrypt.sh` nie wystawia certyfikatu od razu.
   Istniejący klaster ma już sekret `brevo_smtp_password`, używany także przez
   inne usługi. Nie uruchamiaj `06-docker-secrets.sh` na potrzeby tego wdrożenia:
   ten wrapper synchronizuje pozostałe sekrety z Bitwarden. Przy instalacji
   od zera potrzebne są również sekrety pozostałych usług.
4. Wdróż release przez istniejący workflow `update cluster`. Nowa konfiguracja
   Nginx udostępni HTTP-01 dla nowej domeny oraz proxy HTTP/WebSocket.
   Do kolejnego kroku certyfikat może jeszcze nie obejmować nowego hosta.
5. Na managerze uruchom:

   ```bash
   sudo /srv/cluster/bin/renew-certificates
   ```

   Certbot rozszerzy dotychczasowy certyfikat o nową domenę i skrypt podmieni
   sekrety gatewaya. Przy kolejnych odnowieniach korzysta z istniejącego timera.
6. Sprawdź poprawność certyfikatu i odpowiedź `https://vault.grzegorzewski.pl/alive`,
   zaloguj się do `/admin` i zaproś pierwszego użytkownika. Nie włączaj
   publicznej rejestracji, aby utworzyć pierwsze konto. Sprawdź wysłanie
   zaproszenia i logowanie klienta Bitwarden.

Ustawienia zapisane przez panel administratora w `/data/config.json` mają
pierwszeństwo przed zmiennymi środowiskowymi stacka. Zmiana tokena w Docker
Secrets nie zadziała, jeśli panel zapisał własną wartość `admin_token`.
Obowiązują także dotychczasowe zasady wymiany używanych sekretów z instrukcji
Ansible.

## Kopie zapasowe i odtwarzanie

Ansible instaluje na hoście usługi polecenie
`sudo /srv/cluster/bin/backup-vaultwarden` i uruchamia je co godzinę,
15 minut po pełnej godzinie. Skrypt używa SQLite Online Backup API,
sprawdza integralność bazy, pakuje dane oraz odczytuje archiwum przed jego
atomowym opublikowaniem. Baza korzystająca z WAL jest obsługiwana bez
kopiowania aktywnego pliku WAL.

Archiwum `/srv/cluster/backups/vaultwarden/vaultwarden-<UTC>.tar.gz`
zawiera bazę jako `db.sqlite3`, załączniki, Sends, klucze i ewentualny
`config.json`. Pomija cache ikon, pliki tymczasowe i aktywne pliki SQLite.
Katalog i pliki są dostępne wyłącznie dla roota. Kopia bazy jest spójna;
pliki załączników są archiwizowane podczas pracy serwera, więc operacje na
załącznikach równoczesne z backupem nie stanowią jednej transakcji z bazą.

[Downloader](../tools/backups-downloader/README.md) pobiera archiwa do
`VAULTWARDEN`, sprawdza SHA-256 i usuwa zdalną kopię po udanym transferze,
tak jak dla pozostałych źródeł. Uruchamiaj go regularnie, aby kopie trafiały
poza host klastra. Sam cron tworzy kopie lokalne, bez automatycznej retencji.
Archiwa zawierają również wrażliwe klucze i konfigurację; przechowuj je
na chronionym nośniku.

Aby odtworzyć dane:

1. Zatrzymaj usługę: `docker service scale application_vaultwarden=0`.
   Poczekaj na zakończenie zadania przed zmianą plików.
2. Zachowaj dotychczasowy katalog danych jako kopię ratunkową i utwórz
   pusty `/srv/cluster/data/vaultwarden` z właścicielem 1000:1000 i prawami 0700.
3. Rozpakuj zaufane archiwum do pustego katalogu. Nie nakładaj go na stare
   pliki `db.sqlite3-wal` i `db.sqlite3-shm`. Przywróć właściciela 1000:1000
   dla całej zawartości.
4. Upewnij się, że sekret administratora i Brevo są nadal dostępne, i uruchom
   usługę: `docker service scale application_vaultwarden=1`.
5. Sprawdź logowanie, synchronizację i pobieranie załącznika. Podczas
   odtwarzania nie uruchamiaj workflow wdrożeniowego, który przywraca jedną replikę.

### Próba odtworzenia na osobnej instancji

Ćwiczenie wykonuj na kopii danych, poza usługą produkcyjną. Dzięki temu można
sprawdzić rzeczywisty backup bez przestoju i bez cofania bieżących zapisów.

1. Wybierz najnowsze archiwum na hoście usługi. Pobierz je bez usuwania
   zdalnej kopii i porównaj SHA-256 obu plików. Downloader usuwa pobrane kopie
   z serwera, dlatego do tej próby użyj osobnego odczytu przez SSH.
2. Utwórz osobny katalog z prawami 0700 i rozpakuj archiwum do pustego
   podkatalogu danych. Odrzuć wpisy archiwum wychodzące poza katalog docelowy
   oraz dowiązania. Plikom nadaj prawa 0600. Sprawdź bazę przez
   `PRAGMA integrity_check` i zapisz liczby użytkowników, wpisów, organizacji
   oraz załączników, bez wypisywania ich treści.
3. Zachowaj oryginalne archiwum. Wyłącznie w rozpakowanej kopii zastąp
   `config.json` pustym obiektem `{}`, aby ustawienia produkcyjne nie
   nadpisały konfiguracji testowej, w szczególności adresu serwera i poczty.
4. Uruchom obraz w wersji używanej przy wykonaniu backupu, obecnie
   `vaultwarden/server:1.37.5`, z osobnym katalogiem `/data`. Ustaw
   `DOMAIN=https://localhost:19443`, `ROCKET_PORT=8080`,
   `SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=false` i
   `PUSH_ENABLED=false`. Nie przekazuj sekretów produkcyjnych.
5. Umieść Vaultwarden w osobnej sieci Docker z opcją `--internal`, bez innych
   usług produkcyjnych. Dostęp z przeglądarki udostępnij przez oddzielne proxy
   HTTPS podpięte do tej sieci i zwykłej sieci bridge, publikując port wyłącznie
   jako `127.0.0.1:19443`. Proxy ma przekazywać żądania tylko do testowego
   Vaultwardena. Takie rozwiązanie pozwala używać interfejsu także na wersjach
   Dockera, które nie publikują portów kontenera w sieci wewnętrznej. Proxy
   kończy TLS i przekazuje `X-Forwarded-Proto: https`. Certyfikat musi obejmować
   `localhost` w SAN. Przy certyfikacie lokalnym zaakceptuj wyjątek wyłącznie
   dla adresu próby w przeglądarce; nie zmieniaj globalnie weryfikacji TLS
   klientów. Przed uruchomieniem sprawdź, czy wybrany port jest wolny.
6. Sprawdź odpowiedź 200 przez HTTPS dla `/alive` i strony głównej oraz stan kontenera.
   W przeglądarce zaloguj się kontem istniejącym w chwili backupu, z jego
   hasłem głównym i wymaganym 2FA. Sprawdź odszyfrowanie kilku znanych wpisów,
   dostęp do kolekcji organizacji i pobranie załącznika, jeśli są w kopii.
   Konto, organizacja lub wpis utworzone później nie pojawią się w odtworzeniu.
   Jeżeli konto używa 2FA przez e-mail, samo pominięcie konfiguracji SMTP
   blokuje logowanie komunikatem „No enabled and usable two factor providers
   are available for this account”. W izolowanej sieci uruchom lokalny SMTP,
   np. MailHog, i skonfiguruj testowy Vaultwarden: `_enable_smtp=true`,
   `_enable_email_2fa=true`, `smtp_host` wskazujący kontener skrzynki,
   `smtp_port=1025`, `smtp_security=off` oraz testowy `smtp_from`.
   Brak TLS jest dopuszczony tu wyłącznie w osobnej, lokalnej sieci ćwiczenia.
   Udostępnij interfejs skrzynki tylko na loopback przez osobne proxy;
   kod z wiadomości testowej przepisuje użytkownik. Nie wypisuj kodów
   w raporcie ani logach weryfikacji. Ten wariant sprawdza zachowanie
   odtworzonego konta z e-mailowym 2FA, ale nie potwierdza dostarczania
   poczty przez Brevo ani dostępu do rzeczywistej skrzynki odbiorczej.
7. Zapisz datę kopii, sumę kontrolną i wynik kontroli technicznej oraz ręcznej.
   Brak organizacji lub załączników w kopii oznacza, że ich odtwarzania nie
   sprawdzono. Sama odpowiedź `/alive` i poprawna baza nie potwierdzają
   możliwości odszyfrowania sejfu.
8. Po ćwiczeniu zatrzymaj i usuń wyłącznie kontenery oraz sieć próby. Usuń
   rozpakowane dane po zakończeniu sprawdzania; oryginalny backup zachowaj
   zgodnie z zasadami przechowywania kopii.

Ta próba weryfikuje dane sejfu. Nie sprawdza odtworzenia hosta Swarm, DNS,
certyfikatów, sekretów ani działania poczty produkcyjnej. Nie wyłączaj 2FA
w kopii tylko po to, aby uznać ćwiczenie za zakończone.

## Weryfikacja zmian

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
./gradlew clusterRelease
```

Test backupu odtwarza bazę z zatwierdzonymi danymi zapisanymi w WAL,
sprawdza pliki i prawa dostępu oraz odrzucenie brakującej lub uszkodzonej bazy.
Nie zastępuje okresowego odtworzenia rzeczywistego sejfu na osobnej instancji.

Źródła: [konfiguracja Vaultwarden](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/.env.template),
[kopie zapasowe](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault),
[rejestracja i zaproszenia](https://github.com/dani-garcia/vaultwarden/wiki/Disable-registration-of-new-users).
