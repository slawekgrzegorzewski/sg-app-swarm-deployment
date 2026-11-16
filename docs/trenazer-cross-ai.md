# Aktywacja oceny CROSS przez OpenAI

Integracja działa w backendzie Accountant. Jej kontrakt, model i dane wysyłane
poza klaster opisuje [backend](../../sg-app/docs/agents/trenazer-cfop.md#ocena-cross-przez-openai).
Ustawienia integracji znajdują się w
[`apps/configs/application/application.yml.tmpl`](../apps/configs/application/application.yml.tmpl)
pod `cube-trainer.feedback`: `enabled: true`, `model: gpt-6-luna`,
`reasoning: high`, endpoint i interwał odpytywania. Lokalny backend ma w swoim `application.yml`
`enabled: false`. Ustawienia feedbacku nie korzystają ze zmiennych środowiskowych.

Standardowy stack aplikacji wymaga sekretu `openai_api_key` i montuje go tylko
w backendzie jako `/run/secrets/openai_api_key`. Nie ma osobnej nakładki ani
warunkowej aktywacji na podstawie obecności sekretu.

Przed wdrożeniem dodaj ukryte pole własne `openai_api_key` do wpisu
`SG App secrets` w Vaultwarden. Wartością jest klucz projektu OpenAI.
Pole jest zarządzane przez standardową synchronizację Ansible, tak jak pozostałe
sekrety backendu. Z katalogu głównego repozytorium, po skonfigurowaniu `bw`:

```bash
export BW_SESSION="$(bw unlock --raw)"
./ansible/06-docker-secrets.sh home apply
bw lock
unset BW_SESSION
```

Szczegóły opisuje [instrukcja Bitwarden i Ansible](../ansible/README.md#sekrety-z-lokalnego-bitwarden).
Błąd `service backend: secret not found: openai_api_key` oznacza, że przed
wdrożeniem trzeba utworzyć ten sekret przez aktualny playbook, a następnie
ponowić wdrożenie aplikacji. Tryb `check` nie tworzy sekretów.
Istniejący sekret używany przez usługę jest pomijany; jego rotacja wymaga
osobnej operacji.

Nie dodawaj klucza do plików współdzielonych, Docker Configs, frontendu ani opisu
zadania. Użyj klucza projektu OpenAI z dostępem do wybranego modelu i ustaw
odpowiedni budżet w projekcie.

V54 i V55 pozostają bez zmian. Pola oceny AI dodaje migracja V56 przy
wdrożeniu backendu, zachowując istniejące próby i katalog. Nie resetuj bazy
ani nie zmieniaj historii Flyway. Kolejność: backend z V56, potem frontend; backend wymaga
wcześniej utworzonego sekretu `openai_api_key`. Nowy release wdrażaj
przez standardowy workflow.

Po aktywacji wykonaj smart próbę CROSS i sprawdź kolejno statusy oczekiwania,
gotowy feedback, odczyt po przeładowaniu oraz błąd i ponowienie oceny. Backend
musi mieć dostęp HTTPS do `api.openai.com`. W logach nie wypisuj nagrań,
klucza ani pełnych odpowiedzi błędu dostawcy.

Model zmieniaj przez `cube-trainer.feedback.model` w pliku konfiguracji aplikacji.
Poziom reasoning zmieniaj przez `cube-trainer.feedback.reasoning`; klient
przekazuje go jako `reasoning.effort` w Responses API. Model musi obsługiwać ten parametr. Nie testuj zmiany przez rzeczywiste płatne wywołania
bez skonfigurowanego klucza i świadomej aktywacji.
