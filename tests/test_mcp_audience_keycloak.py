import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "apps/tools/create-mcp-clients.py"
SPEC = importlib.util.spec_from_file_location("mcp_clients_integration", SCRIPT)
CLIENTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENTS)
RESOURCE = "https://mcp.grzegorzewski.pl/mcp"


@unittest.skipUnless(os.environ.get("SG_KEYCLOAK_INTEGRATION") == "1" and shutil.which("docker"),
                     "Set SG_KEYCLOAK_INTEGRATION=1 with Docker available")
class McpAudienceKeycloakTest(unittest.TestCase):
    def test_repairs_real_mapper_output_without_changing_users_or_secrets(self):
        name = "sg-mcp-audience-test-" + uuid.uuid4().hex[:12]
        with tempfile.TemporaryDirectory(prefix="sg-mcp-audience-test-") as temporary:
            directory = Path(temporary).resolve()
            for realm in ("sg", "sg-test"):
                clients = CLIENTS.load_clients(realm)
                for client in clients:
                    mapper = client["protocolMappers"][0]
                    mapper["config"]["included.client.audience"] = "sg-api"
                    client["protocolMappers"] = [mapper]
                    if not client["publicClient"]:
                        client["secret"] = "local-test-client-secret"
                clients.append({"clientId": "sg-api", "protocol": "openid-connect", "publicClient": True})
                definition = {"realm": realm, "enabled": True, "sslRequired": "none", "clients": clients,
                              "users": [{"username": "audience-test-user", "enabled": True,
                                         "email": "audience-test@example.invalid", "emailVerified": True}]}
                (directory / f"{realm}-realm.json").write_text(json.dumps(definition))
            self.command("docker", "run", "-d", "--name", name, "-p", "127.0.0.1::8080",
                         "-e", "KC_BOOTSTRAP_ADMIN_USERNAME=local-test-admin",
                         "-e", "KC_BOOTSTRAP_ADMIN_PASSWORD=local-test-admin-password",
                         "-v", f"{directory}:/opt/keycloak/data/import:ro",
                         "quay.io/keycloak/keycloak:26.5.7", "start-dev", "--import-realm")
            try:
                port = self.command("docker", "inspect", "--format",
                                    '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}', name).strip()
                base = f"http://127.0.0.1:{port}"
                payload = urllib.parse.urlencode({"grant_type": "password", "client_id": "admin-cli",
                                                   "username": "local-test-admin", "password": "local-test-admin-password"}).encode()
                deadline = time.monotonic() + 90
                while True:
                    try:
                        with urllib.request.urlopen(base + "/realms/master/protocol/openid-connect/token", payload, timeout=3) as response:
                            admin_token = json.load(response)["access_token"]
                        break
                    except (urllib.error.URLError, ConnectionError):
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(0.5)

                def get(realm, path):
                    request = urllib.request.Request(base + f"/admin/realms/{realm}/" + path,
                                                     headers={"Authorization": "Bearer " + admin_token})
                    with urllib.request.urlopen(request, timeout=10) as response:
                        return json.load(response)

                def audiences(realm, client_id, user_id):
                    query = urllib.parse.urlencode({"userId": user_id, "scope": "openid email"})
                    token = get(realm, f"clients/{client_id}/evaluate-scopes/generate-example-access-token?{query}")
                    value = token.get("aud", [])
                    return {value} if isinstance(value, str) else set(value)

                for realm in ("sg", "sg-test"):
                    with self.subTest(realm=realm):
                        users = get(realm, "users")
                        user_id = next(user["id"] for user in users if user["username"] == "audience-test-user")
                        clients = get(realm, "clients")
                        selected = [client for client in clients if client["clientId"] in CLIENTS.CLIENT_IDS]
                        chatgpt = next(client for client in selected if client["clientId"] == "sg-mcp-chatgpt")
                        secret = get(realm, f"clients/{chatgpt['id']}/client-secret")
                        for client in selected:
                            self.assertIn("sg-api", audiences(realm, client["id"], user_id))
                            self.assertNotIn(RESOURCE, audiences(realm, client["id"], user_id))
                        environment = dict(os.environ, KEYCLOAK_ADMIN_TOKEN=admin_token)
                        command = [sys.executable, str(SCRIPT), "--server-url", base, "--realm", realm,
                                   "--sync-audience", "--apply"]
                        subprocess.run(command, env=environment, capture_output=True, text=True, check=True, timeout=30)
                        for client in selected:
                            self.assertTrue({RESOURCE, "sg-api"}.issubset(audiences(realm, client["id"], user_id)))
                        mappers = {client["id"]: get(realm, f"clients/{client['id']}/protocol-mappers/models") for client in selected}
                        subprocess.run(command, env=environment, capture_output=True, text=True, check=True, timeout=30)
                        for client in selected:
                            self.assertEqual(mappers[client["id"]], get(realm, f"clients/{client['id']}/protocol-mappers/models"))
                        self.assertEqual(users, get(realm, "users"))
                        self.assertEqual(secret, get(realm, f"clients/{chatgpt['id']}/client-secret"))
            finally:
                self.command("docker", "rm", "-f", name)

    @staticmethod
    def command(*arguments):
        return subprocess.run(arguments, capture_output=True, text=True, check=True, timeout=60).stdout


if __name__ == "__main__":
    unittest.main()
