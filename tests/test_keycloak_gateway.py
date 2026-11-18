import shutil
import ssl
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMAGE = "nginx:1.25.4-bookworm"
BUFFER_SETTINGS = """            proxy_buffer_size 16k;
            proxy_buffers 8 16k;
            proxy_busy_buffers_size 32k;
"""


@unittest.skipUnless(shutil.which("docker") and shutil.which("openssl"), "Docker and OpenSSL are required")
class KeycloakGatewayTest(unittest.TestCase):
    def test_large_keycloak_response_headers_fit_only_with_configured_buffers(self):
        configuration = (ROOT / "apps/configs/core/nginx.conf").read_text()
        self.assertIn(BUFFER_SETTINGS, configuration)
        suffix = uuid.uuid4().hex[:12]
        network = f"sg-keycloak-header-test-{suffix}"
        with tempfile.TemporaryDirectory(prefix="sg-keycloak-header-test-") as temporary:
            directory = Path(temporary).resolve()
            certificate = directory / "gateway.crt"
            key = directory / "gateway.key"
            self.command("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                         "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1",
                         "-keyout", str(key), "-out", str(certificate))
            context = ssl.create_default_context(cafile=str(certificate))
            self.command("docker", "network", "create", network)
            try:
                for configured in (False, True):
                    with self.subTest(configured_buffers=configured):
                        name = f"{network}-{int(configured)}"
                        content = configuration if configured else configuration.replace(BUFFER_SETTINGS, "")
                        cookie_value = "a" * 3000
                        cookies = "".join(
                            f'        add_header Set-Cookie "AUTH_TEST{index}={cookie_value}" always;\n'
                            for index in range(3)
                        )
                        upstream = '\n    server {\n        listen 8080;\n' + cookies + '        return 200 "test-keycloak";\n    }\n'
                        position = content.rfind("}")
                        config = directory / f"nginx-{int(configured)}.conf"
                        config.write_text(content[:position] + upstream + content[position:])
                        self.command("docker", "run", "-d", "--name", name, "--network", network,
                                     "--network-alias", "application_keycloak", "-p", "127.0.0.1::443",
                                     "-v", f"{config}:/etc/nginx/nginx.conf:ro",
                                     "-v", f"{certificate}:/run/secrets/gateway.crt:ro",
                                     "-v", f"{key}:/run/secrets/gateway.key:ro", IMAGE)
                        try:
                            self.command("docker", "exec", name, "nginx", "-t")
                            port = self.command("docker", "inspect", "--format",
                                                '{{(index (index .NetworkSettings.Ports "443/tcp") 0).HostPort}}', name).strip()
                            request = urllib.request.Request(f"https://127.0.0.1:{port}/test-only-oauth",
                                                             headers={"Host": "auth.grzegorzewski.pl"})
                            deadline = time.monotonic() + 10
                            while True:
                                try:
                                    response = urllib.request.urlopen(request, context=context, timeout=3)
                                    break
                                except urllib.error.HTTPError as error:
                                    response = error
                                    break
                                except (urllib.error.URLError, ConnectionError):
                                    if time.monotonic() >= deadline:
                                        raise
                                    time.sleep(0.1)
                            with response:
                                self.assertEqual(200 if configured else 502, response.code)
                                if configured:
                                    self.assertEqual(9033, sum(len(cookie) for cookie in response.headers.get_all("Set-Cookie")))
                                    self.assertEqual(b"test-keycloak", response.read())
                                else:
                                    logs = self.command("docker", "logs", name)
                                    self.assertIn("upstream sent too big header", logs)
                        finally:
                            self.command("docker", "rm", "-f", name)
            finally:
                self.command("docker", "network", "rm", network)

    @staticmethod
    def command(*arguments):
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError(f"{arguments[:3]}: {result.stderr[-2000:]}")
        return result.stdout + result.stderr


if __name__ == "__main__":
    unittest.main()
