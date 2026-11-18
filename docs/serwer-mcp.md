# Serwer MCP w Swarmie

Stack `application` zawiera usługę `mcp`, korzystającą z obrazu
`public.registry.grzegorzewski.pl/mcp:${MCP_IMAGE_TAG:-latest}`.
Obraz publikuje workflow `Build MCP Docker image` w repozytorium backendu.
[Budowanie i uruchamianie obrazu](../../sg-app/docs/agents/serwer-mcp.md).

Usługa działa na nodzie z etykietą `workload.application`, w jednej replice,
w sieci `application_network`. Endpoint wewnątrz tej sieci to
`http://application_mcp:8080/mcp`. Logi trafiają do wspólnego sysloga
z tagiem `application_mcp`. Aktualizacja używa `start-first` i rollbacku
w przypadku błędu aktualizacji.

Publiczny endpoint MCP to `https://mcp.grzegorzewski.pl/mcp`.
Gateway przekazuje ruch HTTPS do `application_mcp:8080`, zachowując ścieżkę,
nagłówki i identyfikator sesji MCP. Buforowanie odpowiedzi i żądań jest wyłączone,
a timeout strumienia wynosi godzinę, aby umożliwić komunikację Streamable HTTP/SSE.
HTTP przekierowuje na HTTPS kodem 308, zachowując metodę żądania.
Ścieżka `/.well-known/acme-challenge/` pozostaje dostępna na HTTP dla Certbota.

MCP nie wymaga bazy ani sekretów aplikacji. Port usługi nie jest publikowany
bezpośrednio na hoście; ruch publiczny przechodzi przez gateway.
Każde żądanie MCP, także `test_ping`, wymaga tokenu OAuth z Keycloaka.

## OAuth 2.1, ChatGPT i PKCE

Keycloak jest serwerem autoryzacji. Aplikacja MCP weryfikuje tokeny dostępu;
gateway przekazuje nagłówek `Authorization` i publiczne metadane zasobu
`https://mcp.grzegorzewski.pl/.well-known/oauth-protected-resource/mcp`.
Odpowiedź `401` wskazuje ten adres w `WWW-Authenticate`.

Realmy `sg` i `sg-test` deklarują osobne klienty:

| Klient             | Typ                               | Przeznaczenie              |
| ------------------ | --------------------------------- | -------------------------- |
| `sg-mcp-chatgpt`   | Poufny, client secret + PKCE S256 | Połączenie z ChatGPT       |
| `sg-mcp-inspector` | Publiczny, PKCE S256              | Testy lokalnym Inspectorem |

Oba klienty mają włączony wyłącznie Authorization Code, bez Implicit,
Password Grant i Service Accounts. Każdy klient ma dwa osobne mappery Audience:
`MCP resource audience` z `Included Custom Audience` równym URI MCP oraz
`Accountant API audience` z `Included Client Audience` równym `sg-api`.
W obu włączamy Add to access token i wyłączamy Add to ID token.
Keycloak 26.5.7 traktuje custom audience jako fallback: wypełnienie obu pól
w jednym mapperze dodaje wyłącznie client audience. Dlatego nie łączymy ich
w jednym mapperze. Osobne mappery pozwalają odczytywać własne próby w Accountant.
MCP wymaga scope `openid`; opcjonalne `email` i `profile` obsługują
standardowe mechanizmy OIDC. Klient `sg-mcp-chatgpt` ma przypisany
`offline_access` jako optional client scope, ponieważ ChatGPT żąda go przy logowaniu.
Pozwala to wystawić offline refresh token zgodnie z polityką sesji Keycloaka.
Wystawienie wymaga też roli realmowej `offline_access` u użytkownika;
standardowo jest ona częścią domyślnych ról Keycloaka. Jeśli logowanie zakończy się
`Offline tokens not allowed for the user or client`, sprawdź Role mapping
danego użytkownika. Skrypt synchronizacji scope’ów nie nadaje ról użytkownikom.
Nie dodajemy globalnej listy `clientScopes`,
ponieważ zmieniłaby tworzenie domyślnych scope’ów przy imporcie realmu.
Tokeny zwykłego klienta `sg-frontend` nie mają audience MCP i są odrzucane.

### Konfiguracja ChatGPT

1. Dodaj losowy, silny sekret jako pole własne `keycloak_mcp_chatgpt_client_secret`
   we wpisie `SG App secrets` w Vaultwarden. Utrzymuj tę samą wartość w ustawieniach OAuth ChatGPT.
2. Uruchom istniejącą procedurę tworzenia Docker secrets przed aktualizacją
   stacka. Sekret o tej nazwie jest montowany wyłącznie w Keycloaku;
   skrypt startowy podstawia go do definicji klienta.
3. W konfiguracji połączenia MCP ChatGPT wybierz OAuth i podaj URL
   `https://mcp.grzegorzewski.pl/mcp`, Client ID `sg-mcp-chatgpt` i Client Secret
   z poprzedniego kroku. Scope: `openid`, a jeśli klient ich żąda, także `email profile`.
   ChatGPT może dodatkowo wysłać `offline_access`; jest dopuszczony w konfiguracji klienta.
4. Sprawdź dokładny redirect URI pokazany przez ChatGPT. W konfiguracji
   klienta dopuszczony jest `https://chatgpt.com/connector_platform_oauth_redirect`.
   Jeżeli panel pokazuje `https://chatgpt.com/connector/oauth/<callback_id>`,
   dodaj dokładnie ten adres do `redirectUris` klienta w definicji realmu,
   bez wildcardów.

Keycloak 26.5.7 publikuje obsługę identyfikacji issuera RFC 9207 i zwraca `iss`
w callbacku. Umożliwia to stabilny redirect URI obsługiwany przez ChatGPT.
Odnowienie tokenów klienta ChatGPT używa jego sekretu; publiczny klient Inspector
nie otrzymuje refresh tokenów.

Nie włączamy anonimowej rejestracji klientów DCR ani CIMD: ChatGPT używa
wstępnie zarejestrowanego klienta. Keycloak 26.5.7 nie interpretuje parametru
`resource` RFC 8707. Stosujemy opisany w dokumentacji tej wersji mechanizm
stałego audience dla dedykowanego klienta. Zapewnia on walidację odbiorcy tokenu
w MCP; nie oznacza pełnej obsługi RFC 8707 po stronie Keycloaka.

[Wymagania ChatGPT OAuth](https://developers.openai.com/plugins/build/auth)
oraz [ograniczenia i konfiguracja Keycloak 26.5.7](https://github.com/keycloak/keycloak/blob/26.5.7/docs/guides/securing-apps/mcp-authz-server.adoc).

### Wdrożenie OAuth

#### Dodanie klientów przez Admin API

Skrypt `apps/tools/create-mcp-clients.py` odczytuje wyłącznie definicje
`sg-mcp-chatgpt` i `sg-mcp-inspector` z właściwego pliku realmu.
Domyślnie wyświetla adresy żądań i payloady z ukrytym sekretem, bez połączenia
z serwerem. Z katalogu głównego repozytorium:

```sh
python3 apps/tools/create-mcp-clients.py --realm sg
```

Wykonanie przygotowanych wywołań:

```sh
python3 apps/tools/create-mcp-clients.py --realm sg --apply
```

Przy błędach autoryzacji uruchom najpierw kontrolę samego odczytu:

```sh
python3 apps/tools/create-mcp-clients.py --realm sg-test --check-auth
```

Ten tryb wykonuje wyłącznie GET, pokazuje issuer, klienta, typ i termin ważności
JWT odczytane lokalnie oraz status żądania. Nie pokazuje samego tokenu.
Odczyt claims nie potwierdza autentyczności JWT; autoryzację ocenia Keycloak.
Błąd wskazuje metodę i adres wywołania, więc można rozróżnić nieudany odczyt
od próby utworzenia klienta. Skrypt usuwa z wejścia zewnętrzne spacje,
cudzysłowy oraz opcjonalny prefiks `Authorization: Bearer`.
Jeśli ustawiono `KEYCLOAK_ADMIN_TOKEN`, skrypt używa tej wartości zamiast pytać
o nowy token. Przed ręcznym ponowieniem z nowym tokenem usuń tę zmienną
poleceniem `unset KEYCLOAK_ADMIN_TOKEN` w Bashu.

Na macOS długi JWT może przekroczyć limit pojedynczego wiersza terminala
przy ukrytym wejściu `getpass`. Aby ominąć ten limit, skopiuj świeży nagłówek
Authorization w przeglądarce i przekaż go bezpośrednio ze schowka:

```sh
pbpaste | python3 apps/tools/create-mcp-clients.py --realm sg-test --check-auth --token-stdin
```

Po poprawnym teście ponownie skopiuj token i wykonaj:

```sh
pbpaste | python3 apps/tools/create-mcp-clients.py --realm sg-test --apply --token-stdin
```

`--token-stdin` ma pierwszeństwo przed zmienną `KEYCLOAK_ADMIN_TOKEN`.
Schowek jest odczytywany przez polecenie `pbpaste` uruchomione przez użytkownika;
skrypt nie zapisuje ani nie wyświetla tokenu. Sekret ChatGPT nadal jest
wprowadzany oddzielnie w ukrytym polu terminala.

Skrypt zapyta o token administratora z uprawnieniami do odczytu i tworzenia klientów
w wybranym realmie oraz o Client Secret ChatGPT z Vaultwarden. Dane wejściowe są
ukryte i nie trafiają do pliku ani argumentów procesu. Można zamiast tego przekazać
zmienne środowiskowe `KEYCLOAK_ADMIN_TOKEN` i `KEYCLOAK_MCP_CHATGPT_CLIENT_SECRET`.
Użyj tokenu z własnej uwierzytelnionej sesji Admin Console albo uprawnionego
klienta administracyjnego. Nie używaj tokenu zwykłego klienta MCP.

Skrypt wykonuje tylko:

```text
GET  /admin/realms/sg/clients?clientId=sg-mcp-chatgpt&search=false
GET  /admin/realms/sg/clients?clientId=sg-mcp-inspector&search=false
POST /admin/realms/sg/clients
```

POST jest wykonywany oddzielnie dla każdego brakującego klienta.
Bez `--sync-scopes` istniejący klient jest pomijany: jego konfiguracja i sekret nie są aktualizowane.
Ponowne uruchomienie nie tworzy duplikatów. Użytkownicy, grupy, role i pozostali
klienci nie są modyfikowani; domyślnie nie jest wykonywany import realmu ani PUT/DELETE.
Operacje nie są transakcją: jeśli drugi POST zawiedzie, pierwszy utworzony klient
pozostaje, a kolejne uruchomienie go pomija. Istniejącego klienta z niepoprawnymi
ustawieniami popraw osobno w Admin Console.

Jeśli klient został utworzony przed dodaniem `offline_access`, samo `--apply`
go nie naprawi. Zsynchronizuj brakujące optional scope’y z definicjami realmów:

```sh
pbpaste | python3 apps/tools/create-mcp-clients.py --realm sg --apply --sync-scopes --token-stdin
```

Ten tryb odczytuje scope’y realmu i klienta, a następnie wykonuje wyłącznie
brakujące przypisania `PUT /admin/realms/sg/clients/<client-uuid>/optional-client-scopes/<scope-uuid>`.
Nie aktualizuje reprezentacji klienta, sekretu ani użytkowników i nie usuwa
dotychczasowych przypisań. Ponowne uruchomienie pomija przypisane scope’y.
Dla `sg-test` zmień argument `--realm`. Jeśli `offline_access` nie istnieje
w realmie, skrypt zatrzyma się przed zmianą przypisań.

Alternatywnie: Admin Console → realm `sg` → Clients → `sg-mcp-chatgpt`
→ Client scopes → Add client scope → `offline_access` → Add as optional.
Po zmianie ponów połączenie OAuth w ChatGPT. Nie wymaga to restartu MCP ani Keycloaka.

Dla środowiska testowego podaj `--realm sg-test`; na Windows użyj `python`
zamiast `python3`, jeśli tak nazywa się interpreter. Na innym serwerze użyj
`--server-url https://adres-keycloak`. Skrypt nie podąża za przekierowaniami HTTP.

Skrypt weryfikuje TLS, korzystając z domyślnego magazynu CA Pythona.
Jeśli magazyn nie jest skonfigurowany i nie ustawiono zmiennych `SSL_CERT_FILE`
ani `SSL_CERT_DIR`, może użyć zainstalowanego pakietu `certifi`.
Własny pakiet zaufanych certyfikatów PEM można wskazać przez `--ca-file`.
Nie ma trybu wyłączającego weryfikację certyfikatów.
Na macOS instalacja Pythona z python.org udostępnia `Install Certificates.command`
w katalogu danej wersji Pythona w Aplikacjach; uruchomienie tego polecenia
konfiguruje domyślny magazyn CA dla tej instalacji.

[Kontrakt Keycloak Admin REST API](https://www.keycloak.org/docs-api/26.5.7/rest-api/).

#### Kolejność aktywacji

Najpierw wykonaj backup bazy Keycloaka i utwórz nowy Docker secret.
Następnie zastosuj konfigurację klientów w istniejących realmach i uruchom
Keycloak z nowym sekretem. Import `--import-realm` przy starcie pomija realmy,
które już istnieją: dla istniejącej instalacji dodaj klientów w Admin Console
lub przez Admin API na podstawie plików realmów. Nie usuwaj realmu ani kont
w celu wymuszenia importu. Dopiero potem wdróż nowy obraz MCP przez jego workflow.
Dotychczasowe anonimowe klienty MCP otrzymają od tego momentu `401`.

Weryfikacja: brak tokenu daje `401` z metadanymi, logowanie ChatGPT otwiera
Keycloak, a po powrocie `test_ping` działa. Zły audience lub issuer i wygasły
token muszą zostać odrzucone.

## Domena i certyfikat

DNS `mcp.grzegorzewski.pl` musi wskazywać publiczny adres gatewaya.
Domena jest dodana do `letsencrypt_domains`, więc wspólny certyfikat gatewaya
obejmuje ją po ponownym uruchomieniu roli i odnowieniu certyfikatu.

Kolejność aktywacji:

1. Ustaw rekord DNS i zainstaluj release zawierający nową konfigurację Nginx.
2. Uzgodnij stack `core`, aby gateway obsługiwał HTTP-01 nowej domeny.
3. Uruchom `ansible/05-letsencrypt.sh home apply`, aby zainstalować skrypt
   odnowienia z nową listą domen.
4. Na managerze wykonaj `sudo /srv/cluster/bin/renew-certificates --force-renewal`.
   Skrypt tworzy nowe sekrety TLS i aktualizuje gateway.
5. Sprawdź klientem MCP inicjalizację i `test_ping` pod publicznym endpointem.

Do zakończenia odnowienia istniejący certyfikat może jeszcze nie obejmować
nowej domeny. [Mechanizm rotacji certyfikatów](../ansible/README.md#lets-encrypt-i-rotacja-certyfikatów).

## Pierwsze wdrożenie

1. Zainstaluj release infrastruktury z definicją usługi `mcp` oraz zaktualizowanymi
   skryptami `set-image-tag.sh` i `start-stack.sh`.
2. Uruchom ręcznie workflow `Build MCP Docker image` w repozytorium backendu.
   Publikuje on obraz z niezmiennym tagiem i wykonuje dwa polecenia managera:

```sh
/srv/cluster/current/tools/set-image-tag.sh mcp <image-tag>
/srv/cluster/current/tools/start-stack.sh application
```

Do zakończenia publikacji pierwszego obrazu nowa usługa może pozostawać
oczekująca na obraz `latest`; workflow ustawia właściwy tag i uzgadnia stack.
Kolejne wdrożenia wymagają już tylko uruchomienia workflowu backendu.
Zmiany źródeł nie wdrażają się automatycznie przed publikacją obu repozytoriów.

Tag `MCP_IMAGE_TAG` jest zapisywany razem z pozostałymi tagami
w `/srv/cluster/image-tags.env`, dzięki czemu release klastra zachowuje wybrany obraz.
Rollback do release'u sprzed obsługi MCP wymaga usunięcia tego wpisu
z pliku tagów, ponieważ wcześniejsze skrypty odrzucają nieznane ustawienia.

## Narzędzia CROSS i przejście z automatycznej oceny

MCP udostępnia `list_cross_attempts` i `get_cross_attempt` przez istniejący
endpoint `/mcp`. To narzędzia protokołu MCP, bez nowych publicznych tras REST.
[Argumenty i dane](../../sg-app/docs/agents/serwer-mcp.md#narzędzia-cross).
Swarm ustawia `ACCOUNTANT_GRAPHQL_URL=http://application_backend:8080/graphql`.
MCP nie ma dostępu do bazy ani sekretu serwisowego Accountant. Przekazuje token
bieżącego użytkownika, wystawiony dla obu usług. Accountant weryfikuje go
ponownie i sprawdza uprawnienia domenowe oraz właściciela próby.

Dla istniejących klientów samo uruchomienie Keycloaka nie aktualizuje mappera.
Podgląd i zastosowanie zmiany dla obu realmów:

```sh
python3 apps/tools/create-mcp-clients.py --realm sg --sync-audience
python3 apps/tools/create-mcp-clients.py --realm sg --sync-audience --apply
python3 apps/tools/create-mcp-clients.py --realm sg-test --sync-audience --apply
```

Tryb `--sync-audience` wykonuje GET mapperów i uzgadnia dwa osobne mappery
przez POST/PUT. Naprawia wcześniejszy mapper MCP z wpisanym `sg-api`:
usuwając `included.client.audience` z mappera MCP, zachowuje jego custom URI
i dodaje dedykowany mapper `Accountant API audience` dla `sg-api`.
Przed pierwszym zapisem sprawdza oba mappery klienta; nie nadpisuje nieznanych
audience ani mapperów o innym typie. Zachowuje dodatkowe ustawienia mapperów,
sekret klienta i użytkowników. Ponowne wykonanie jest idempotentne.
Po zmianie odnów token lub połącz MCP ponownie, aby `aud` zawierało URI MCP i `sg-api`.
Użytkownik musi mieć konto powiązane przez email i uprawnienia Accountant w domenie.

Kolejność wdrożenia usunięcia automatycznej oceny:

1. Wykonaj backup Accountant, jeśli chcesz zachować stare teksty ocen. V57 trwale
   usuwa kolumny ocen i statusy; próby, nagrania oraz analiza CFOP pozostają.
2. Wdróż frontend bez pól oceny i pollingu. Jest zgodny ze starym backendem.
   Zamknij lub odśwież stare sesje przeglądarki przed usunięciem pól GraphQL.
3. Zainstaluj release konfiguracji stacka bez sekretu OpenAI w backendzie
   i z adresem Accountant dla MCP. Zsynchronizuj mappery klientów poleceniami powyżej.
4. Wdróż Accountant z V57 i nowymi zapytaniami. Stara instancja backendu musi być
   zatrzymana przed migracją (aktualizacja `stop-first`); nie uruchamiaj jej workera
   równolegle z usuwaniem kolumn. Rollback starego obrazu wymaga przywrócenia schematu
   z backupu, ponieważ V57 jest niezgodna ze starym kodem.
5. Wdróż MCP przez jego workflow, połącz klienta ponownie, wykonaj listowanie
   i pobranie próby. Sprawdź również brak dostępu do UUID innego użytkownika.

Konfiguracja backendu i Ansible nie używa już `openai_api_key`. Istniejący
sekret Docker i wpis Vaultwarden nie są automatycznie kasowane. Nie ma potrzeby
ich odtwarzania do działania nowych narzędzi.

## Błąd 502 podczas logowania OAuth

Discovery lub strona główna Keycloaka mogą działać, gdy konkretne żądanie
Authorization Code zwraca 502. Parametry OAuth (m.in. `state` i `id_token_hint`)
mogą zwiększać nagłówki odpowiedzi Keycloaka, w tym ciasteczka sesji logowania.
Gateway musi pomieścić cały nagłówek odpowiedzi upstream w `proxy_buffer_size`.
Domyślne 4/8 KiB może być niewystarczające.

Location proxy domeny `auth.grzegorzewski.pl` ustawia `proxy_buffer_size 16k`,
`proxy_buffers 8 16k` i `proxy_busy_buffers_size 32k`. Zmiana dotyczy wyłącznie
Keycloaka, bez podnoszenia globalnych limitów żądań i bez wyłączania weryfikacji
OAuth. Przyczynę w logach Nginx identyfikuje `upstream sent too big header
while reading response header from upstream`; przy odczycie logów nie kopiuj
pełnych URL-i logowania ani tokenów.

Wdróż release infrastruktury przez workflow `update cluster`; aktualizacja
stacka `core` uruchomi gateway z nowym configiem. Nie wymaga to restartu Keycloaka
ani ponownego importu realmu. Następnie rozpocznij nowe połączenie OAuth w kliencie.
Sam restart gatewaya ze starym configiem nie zastosuje poprawki.

Test integracyjny wykorzystuje rzeczywisty obraz gatewaya i testowy upstream
z nagłówkiem przekraczającym 8 KiB. Z katalogu repozytorium, przy dostępnym Dockerze
oraz `openssl`:

```sh
python3 -m unittest discover -s tests -p test_keycloak_gateway.py
```

Test tworzy i usuwa wyłącznie własny kontener oraz sieć. Nie łączy się z produkcją.
[Dokumentacja buforowania Nginx](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffer_size).

## Powtarzające się łączenie OAuth po zalogowaniu

Sekwencja `POST .../token → 200`, a następnie `POST /mcp → 401` tuż po
wydaniu tokenu wskazuje na odrzucenie nowego tokenu przez MCP. Sam status
„połączono” w ChatGPT nie potwierdza poprawnej walidacji JWT po stronie zasobu.
Nie zwiększamy czasu ważności tokenów jako obejścia błędnego audience.

Dla Keycloak 26.5.7 sprawdź dwa osobne mappery opisane powyżej. W access tokenie
musi występować zarówno `https://mcp.grzegorzewski.pl/mcp`, jak i `sg-api`.
Jeden mapper z oboma polami powoduje brak URI MCP w `aud` i kolejne 401.
Naprawę istniejących klientów wykonuje aktualny `--sync-audience --apply`;
import realmów przy starcie pomija istniejące realmy i nie zastępuje tej operacji.
Po naprawie rozpocznij nowe połączenie OAuth, aby otrzymać nowy token.

Testy jednostkowe synchronizacji:

```sh
python3 -m unittest discover -s tests -p test_mcp_clients.py
```

Test na rzeczywistym Keycloaku 26.5.7, z tymczasowym kontenerem i testowymi
realmami, weryfikuje audience przed i po naprawie oraz zachowanie sekretów,
użytkowników i idempotencji:

```sh
SG_KEYCLOAK_INTEGRATION=1 python3 -m unittest discover -s tests -p test_mcp_audience_keycloak.py
```

Na PowerShell ustaw najpierw `$env:SG_KEYCLOAK_INTEGRATION='1'`, a następnie
uruchom to samo polecenie Python bez prefiksu zmiennej.
Źródło zachowania mappera:
[AudienceProtocolMapper w Keycloak 26.5.7](https://github.com/keycloak/keycloak/blob/26.5.7/services/src/main/java/org/keycloak/protocol/oidc/mappers/AudienceProtocolMapper.java).
