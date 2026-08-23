# Podsumowanie migracji klastra

Cała infrastruktura została przeniesiona na uzgodniony model oparty na
jednym katalogu głównym: `/srv/cluster`.

## Zaimplementowane zmiany

- katalogi i etykiety `workload.*` są wyznaczane dynamicznie z grup inventory;
- wszystkie bind mounty znajdują się pod `/srv/cluster`, z wyjątkiem socketu
  Dockera;
- stacki mają neutralne nazwy: `core`, `database`, `application` oraz
  `infrastructure`;
- pliki release'u trafiają wyłącznie na managera do
  `/srv/cluster/releases/<release-id>`, a symlink `/srv/cluster/current` jest
  przełączany atomowo;
- konfiguracje są wersjonowanymi Docker configs;
- certyfikaty są wersjonowanymi Docker Swarm secrets;
- Certbot korzysta z trybu `standalone`, gdy gateway nie działa, oraz z
  `webroot`, gdy gateway jest uruchomiony;
- sekrety są pobierane przez 1Password CLI zainstalowane na lokalnym
  kontrolerze Ansible, a nie na serwerze;
- istniejące, nieużywane przez żaden serwis sekrety mogą być aktualizowane;
- `apps/application/secrets/setup_secrets.sh` został tylko przeniesiony, bez
  modyfikowania jego treści;
- aktualne nazwy plików i katalogów nie zawierają `sg`.

Szczegółowa instrukcja znajduje się w [ansible/README.md](ansible/README.md),
a opis zawartości release'u w [apps/README.md](apps/README.md).

## Walidacja

Zakończone pomyślnie zostały:

- budowanie `clusterRelease`;
- test powtarzalności archiwum — SHA-256 był identyczny po ponownym buildzie;
- walidacja wszystkich czterech stacków przez `docker stack config`;
- kontrola składni playbooków przez `ansible-playbook --syntax-check`;
- parsowanie 46 plików YAML;
- kontrola składni wszystkich skryptów Bash;
- porównanie list sekretów w Ansible, stackach i stacku testowym;
- `git diff --check`.

Nie wykonano faktycznego wdrożenia na klaster ani `nginx -t`, ponieważ w
środowisku lokalnym nie był dostępny działający daemon Dockera ani Nginx.

## Pierwsze wdrożenie

1. Wykonać kroki `01`–`05` opisane w `ansible/README.md`.
2. Skopiować stare dane registry oraz statyczne pliki gatewaya, jeżeli mają
   zostać zachowane. Ansible celowo nie kopiuje ani nie usuwa starych danych.
3. Uzyskać pierwszy certyfikat:

   ```bash
   ssh PC2 'sudo /srv/cluster/bin/renew-certificates --standalone'
   ```

4. Upewnić się, że w 1Password istnieje pole
   `op://Private/SG App secrets/htpasswd`.
5. Utworzyć sekrety:

   ```bash
   cd ansible
   ./06-docker-secrets.sh home apply
   ```

6. Uruchomić workflow deploymentu klastra.

## Lokalny deployment środowiska Vagrant

Dla maszyn testowych Vagrant nie należy używać workflow GitHub Actions. Release
można zbudować lokalnie i przesłać bezpośrednio na managera `192.168.56.10`.

Jeżeli maszyny testowe nie mają dostępu do Internetu, certyfikaty można
skopiować z produkcji. Samo skopiowanie plików PEM nie wystarcza — na
testowym managerze trzeba utworzyć Docker Secrets oraz metadane wymagane przez
gateway.

Umieść pliki źródłowe na managerze, np. jako `/tmp/production.crt` oraz
`/tmp/production.key`, a następnie połącz się z nim:

```bash
ssh -i ~/.ssh/ansible-test/vagrant_pc2_ed25519 slawek@192.168.56.10
```

Rozszerzenia `.crt` i `.key` nie określają formatu. Sprawdź nagłówki plików:

```bash
CERT_SOURCE=/tmp/production.crt
KEY_SOURCE=/tmp/production.key

head -n 1 "$CERT_SOURCE"
head -n 1 "$KEY_SOURCE"
```

Jeśli pojawiają się odpowiednio `BEGIN CERTIFICATE` oraz `BEGIN ... PRIVATE
KEY`, pliki są już w formacie PEM. Przygotuj pliki tymczasowe:

```bash
cp "$CERT_SOURCE" /tmp/cert.pem
cp "$KEY_SOURCE" /tmp/privkey.pem
```

Jeśli pliki są w DER, przekonwertuj je do PEM:

```bash
openssl x509 -inform DER -in "$CERT_SOURCE" -out /tmp/cert.pem
openssl pkey -inform DER -in "$KEY_SOURCE" -out /tmp/privkey.pem
```

Jeśli urząd certyfikacji przekazał osobny łańcuch, `fullchain.pem` musi
zawierać najpierw certyfikat domeny, a następnie certyfikaty łańcucha:

```bash
cat /tmp/cert.pem /path/to/chain.pem > /tmp/fullchain.pem
```

Jeżeli `production.crt` jest już pełnym łańcuchem, użyj go bez dodatkowego
łączenia:

```bash
cp /tmp/cert.pem /tmp/fullchain.pem
```

Zainstaluj pliki pod nazwami oczekiwanymi przez Certbota:

```bash
sudo install -d -m 0700 \
  /srv/cluster/certificates/letsencrypt/config/live/grzegorzewski.pl
sudo install -m 0644 /tmp/fullchain.pem \
  /srv/cluster/certificates/letsencrypt/config/live/grzegorzewski.pl/fullchain.pem
sudo install -m 0600 /tmp/privkey.pem \
  /srv/cluster/certificates/letsencrypt/config/live/grzegorzewski.pl/privkey.pem
```

```bash
CERT=/srv/cluster/certificates/letsencrypt/config/live/grzegorzewski.pl/fullchain.pem
KEY=/srv/cluster/certificates/letsencrypt/config/live/grzegorzewski.pl/privkey.pem

if ! sudo test -s "$CERT" || ! sudo test -s "$KEY"; then
  echo "Brak certyfikatu lub klucza: sprawdź ścieżki i uprawnienia." >&2
  exit 1
fi

VERSION=$(sudo sha256sum "$CERT" "$KEY" | sha256sum | cut -c1-16)
CERT_SECRET="gateway_tls_certificate_$VERSION"
KEY_SECRET="gateway_tls_private_key_$VERSION"

sudo docker secret inspect "$CERT_SECRET" >/dev/null 2>&1 || \
  sudo docker secret create "$CERT_SECRET" "$CERT"
sudo docker secret inspect "$KEY_SECRET" >/dev/null 2>&1 || \
  sudo docker secret create "$KEY_SECRET" "$KEY"

TMP=$(mktemp)
printf 'GATEWAY_TLS_CERTIFICATE_SECRET=%s\nGATEWAY_TLS_PRIVATE_KEY_SECRET=%s\n' \
  "$CERT_SECRET" "$KEY_SECRET" > "$TMP"
sudo chown root:slawek "$TMP"
sudo chmod 0640 "$TMP"
sudo mv "$TMP" /srv/cluster/certificates/letsencrypt/current-secrets.env
```

Plik `current-secrets.env` należy tworzyć na nowo dla klastra testowego — nie
kopiować go z produkcji, ponieważ zawiera nazwy produkcyjnych Docker Secrets.

Build uruchom po stronie Windows, jeśli `JAVA_HOME` wskazuje na Windowsowe JDK:

```powershell
cd D:\Development\Projects\sg-app-swarm-deployment
$env:JAVA_HOME = "C:\ścieżka\do\jdk-25"
.\gradlew.bat clusterRelease
```

Następnie w WSL, z katalogu repozytorium, wykonaj transfer i deployment:

Poniższy blok uruchom na lokalnym komputerze kontrolnym, nie w sesji SSH na
`PC2`/managerze. Jeżeli jesteś aktualnie na managerze, najpierw wykonaj
`exit`. Repozytorium znajduje się na komputerze lokalnym pod `/mnt/d/...`, a
manager Vagranta nie ma tego katalogu.

```bash
cd /mnt/d/Development/Projects/sg-app-swarm-deployment

release_id=$(git rev-parse HEAD)
archive=build/distributions/cluster-release.tar.gz
checksum=$(sha256sum "$archive" | awk '{print $1}')
key="$HOME/.ssh/ansible-test/vagrant_pc2_ed25519"
host=192.168.56.10
remote_dir="/tmp/cluster-deploy-$release_id"

mkdir -p "$(dirname "$key")"
if [[ ! -f "$key" ]]; then
  cp ansible-test/.ssh/vagrant_pc2_ed25519 "$key"
fi
chmod 600 "$key"
ssh -i "$key" slawek@"$host" "mkdir -p '$remote_dir'"
scp -i "$key" \
  "$archive" \
  apps/utils/update_cluster.sh \
  slawek@"$host":"$remote_dir"/

ssh -i "$key" slawek@"$host" "
  cd '$remote_dir' &&
  chmod 0755 update_cluster.sh &&
  ./update_cluster.sh cluster-release.tar.gz '$release_id' '$checksum';
  status=\$?;
  cd /;
  rm -rf -- '$remote_dir';
  exit \$status
"
```

Skrypt zainstaluje release w `/srv/cluster/releases/<release-id>`, przełączy
`/srv/cluster/current` i uruchomi stacki na managerze.

## Uwaga dotycząca indeksu Git

W indeksie Git pozostał wcześniejszy wpis
`AD ansible/roles/letsencrypt/templates/renew-sg-application-certs.j2`.
Pliku nie ma już w working tree. Przed commitem należy wykonać `git add -A`,
aby nie zatwierdzić jego starej, staged wersji.
