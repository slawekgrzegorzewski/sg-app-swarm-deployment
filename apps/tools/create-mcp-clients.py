import argparse
import base64
import copy
from datetime import datetime, timezone
import getpass
import json
import os
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


CLIENT_IDS = ("sg-mcp-chatgpt", "sg-mcp-inspector")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def create_tls_context(ca_file):
    context = ssl.create_default_context(cafile=ca_file)
    paths = ssl.get_default_verify_paths()
    if ca_file is None and paths.cafile is None and paths.capath is None and not os.environ.get("SSL_CERT_FILE") and not os.environ.get("SSL_CERT_DIR"):
        try:
            import certifi
        except ImportError:
            raise RuntimeError("Python nie ma certyfikatów CA. Zainstaluj certyfikaty dla Pythona lub podaj --ca-file z zaufanym pakietem CA.") from None
        context.load_verify_locations(cafile=certifi.where())
    return context


def load_clients(realm):
    source = Path(__file__).resolve().parent.parent / "configs" / "application" / f"{realm}-realm.json"
    definitions = json.loads(source.read_text(encoding="utf-8"))["clients"]
    clients = []
    for client_id in CLIENT_IDS:
        matches = [client for client in definitions if client["clientId"] == client_id]
        if len(matches) != 1:
            raise ValueError(f"Oczekiwano jednej definicji klienta {client_id} w {source}.")
        clients.append(matches[0])
    if clients[0].get("secret") != "${KEYCLOAK_MCP_CHATGPT_CLIENT_SECRET}":
        raise ValueError("Definicja ChatGPT musi wskazywać zmienną sekretu, bez zapisanej wartości.")
    return clients


def normalize_token(value):
    token = value.strip()
    if len(token) >= 2 and token[0] == token[-1] and token[0] in ("'", '"'):
        token = token[1:-1].strip()
    if token.lower().startswith("authorization:"):
        token = token.partition(":")[2].strip()
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    if not token or any(character.isspace() for character in token):
        raise ValueError("Wklej kompletny access token z nagłówka Authorization, bez podziału na wiersze.")
    return token


def describe_token(token):
    try:
        payload = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        if not isinstance(claims, dict):
            raise ValueError("Niepoprawne claims JWT.")
    except (IndexError, ValueError, UnicodeDecodeError):
        print("Nie można odczytać metadanych JWT; token zostanie sprawdzony przez Keycloak.")
        return
    print("Metadane JWT odczytane lokalnie, bez weryfikacji podpisu:")
    for key in ("iss", "azp", "typ"):
        value = claims.get(key)
        if isinstance(value, str):
            print(f"  {key}: {value[:200]}")
    expiration = claims.get("exp")
    if isinstance(expiration, (int, float)):
        try:
            valid_until = datetime.fromtimestamp(expiration, timezone.utc)
        except (OverflowError, OSError, ValueError):
            print("  exp: niepoprawny czas ważności")
            return
        remaining = int((valid_until - datetime.now(timezone.utc)).total_seconds())
        print(f"  ważny do: {valid_until.isoformat()} (pozostało {remaining} s według lokalnego zegara)")


def api_request(opener, url, token, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with opener.open(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{request.get_method()} {url}: HTTP {error.code}. Istniejące dane nie są nadpisywane ani usuwane.") from None
    except urllib.error.URLError as error:
        if isinstance(error.reason, ssl.SSLCertVerificationError):
            raise RuntimeError("Nie można zweryfikować certyfikatu TLS. Sprawdź łańcuch certyfikatu serwera i magazyn CA Pythona lub podaj --ca-file. Weryfikacja TLS pozostaje włączona.") from None
        raise


def main():
    parser = argparse.ArgumentParser(description="Dodaje wyłącznie brakujących klientów MCP przez Keycloak Admin API.")
    parser.add_argument("--realm", choices=("sg", "sg-test"), default="sg")
    parser.add_argument("--server-url", default="https://auth.grzegorzewski.pl")
    parser.add_argument("--ca-file", help="Plik PEM z zaufanymi certyfikatami CA.")
    parser.add_argument("--check-auth", action="store_true", help="Sprawdź token przez GET, bez tworzenia klientów.")
    parser.add_argument("--token-stdin", action="store_true", help="Odczytaj token z potoku stdin, bez limitu długości wiersza terminala.")
    parser.add_argument("--apply", action="store_true", help="Wykonaj GET i POST; domyślnie pokaż tylko plan.")
    args = parser.parse_args()
    if args.apply and args.check_auth:
        parser.error("Wybierz --apply albo --check-auth.")
    if args.token_stdin and not (args.apply or args.check_auth):
        parser.error("--token-stdin wymaga --apply albo --check-auth.")
    if args.token_stdin and sys.stdin.isatty():
        parser.error("Przekaż token potokiem, np. pbpaste | python3 apps/tools/create-mcp-clients.py --realm sg-test --check-auth --token-stdin.")
    server = urllib.parse.urlsplit(args.server_url)
    local_http = server.scheme == "http" and server.hostname in ("localhost", "127.0.0.1", "::1")
    if (server.scheme != "https" and not local_http) or not server.hostname or server.username or server.password or server.query or server.fragment:
        raise ValueError("Adres serwera musi używać HTTPS; HTTP jest dozwolone wyłącznie lokalnie.")

    clients = load_clients(args.realm)
    endpoint = f"{args.server_url.rstrip('/')}/admin/realms/{args.realm}/clients"
    if not args.apply and not args.check_auth:
        for client in clients:
            query = urllib.parse.urlencode({"clientId": client["clientId"], "search": "false"})
            print(f"GET {endpoint}?{query}")
            print(f"POST {endpoint} (tylko gdy klient nie istnieje)")
            preview = copy.deepcopy(client)
            if "secret" in preview:
                preview["secret"] = "<sekret podawany przy wykonaniu>"
            print(json.dumps(preview, indent=2, ensure_ascii=False))
        return

    context = create_tls_context(args.ca_file)
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=context))
    if args.token_stdin:
        token = normalize_token(sys.stdin.read())
    else:
        token_from_environment = os.environ.get("KEYCLOAK_ADMIN_TOKEN")
        if token_from_environment:
            print("Używam tokenu ze zmiennej KEYCLOAK_ADMIN_TOKEN.")
        token = normalize_token(token_from_environment or getpass.getpass("Token administratora Keycloak: "))
    if args.check_auth:
        describe_token(token)
    missing = []
    for client in clients:
        query = urllib.parse.urlencode({"clientId": client["clientId"], "search": "false"})
        existing = api_request(opener, f"{endpoint}?{query}", token)
        if args.check_auth:
            print(f"GET {endpoint}?{query}: HTTP 200")
            continue
        if any(item["clientId"] == client["clientId"] for item in existing):
            print(f"Pominięto istniejącego klienta {client['clientId']} (bez zmian konfiguracji i sekretu).")
        else:
            missing.append(client)

    if args.check_auth:
        print("Token pozwala odczytać klientów. Nie wykonano żadnego POST.")
        return

    if any(client["clientId"] == "sg-mcp-chatgpt" for client in missing):
        secret = os.environ.get("KEYCLOAK_MCP_CHATGPT_CLIENT_SECRET") or getpass.getpass("Client Secret ChatGPT z Vaultwarden: ")
        if not secret.strip():
            raise ValueError("Sekret ChatGPT jest wymagany; nie utworzono klientów.")
        for client in missing:
            if client["clientId"] == "sg-mcp-chatgpt":
                client["secret"] = secret

    for client in missing:
        api_request(opener, endpoint, token, client)
        print(f"Utworzono klienta {client['clientId']} w realmie {args.realm}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, EOFError) as error:
        print(f"Błąd: {error}", file=sys.stderr)
        sys.exit(1)
