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
Testowe `test_ping` jest dostępne bez uwierzytelnienia.

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
