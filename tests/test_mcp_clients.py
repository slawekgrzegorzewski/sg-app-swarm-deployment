import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "apps/tools/create-mcp-clients.py"
SPEC = importlib.util.spec_from_file_location("mcp_clients", SCRIPT)
CLIENTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENTS)


class McpClientsTest(unittest.TestCase):
    def test_both_realms_issue_tokens_for_mcp_and_accountant(self):
        for realm in ("sg", "sg-test"):
            for client in CLIENTS.load_clients(realm):
                mapper, = [item for item in client["protocolMappers"] if item["name"] == "MCP resource audience"]
                self.assertEqual("sg-api", mapper["config"]["included.client.audience"])
                self.assertEqual("https://mcp.grzegorzewski.pl/mcp", mapper["config"]["included.custom.audience"])

    def test_sync_updates_only_mapper_and_preserves_existing_configuration(self):
        client = CLIENTS.load_clients("sg")[0]
        mapper = copy.deepcopy(client["protocolMappers"][0])
        mapper["id"] = "mapper-id"
        mapper["config"].pop("included.client.audience")
        mapper["config"]["existing-option"] = "keep"
        original = copy.deepcopy(mapper)
        with patch.object(CLIENTS, "api_request", side_effect=[[mapper], None]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/admin/realms/sg/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(2, api.call_count)
        call = api.call_args_list[1]
        self.assertEqual("https://example/admin/realms/sg/clients/client-id/protocol-mappers/models/mapper-id", call.args[1])
        self.assertEqual({"method": "PUT"}, call.kwargs)
        updated = call.args[3]
        self.assertEqual("sg-api", updated["config"].pop("included.client.audience"))
        self.assertEqual(original, updated)
        self.assertEqual(original, mapper)

    def test_sync_is_idempotent(self):
        client = CLIENTS.load_clients("sg")[0]
        with patch.object(CLIENTS, "api_request", return_value=client["protocolMappers"]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(1, api.call_count)

    def test_does_not_overwrite_ambiguous_or_unexpected_mapper(self):
        client = CLIENTS.load_clients("sg")[0]
        mapper = client["protocolMappers"][0]
        other_audience = copy.deepcopy(mapper)
        other_audience["config"]["included.client.audience"] = "another-api"
        for response in ([mapper, mapper], [dict(mapper, protocolMapper="unexpected")], [other_audience]):
            with patch.object(CLIENTS, "api_request", return_value=response) as api:
                with self.assertRaises(ValueError):
                    CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
            self.assertEqual(1, api.call_count)


if __name__ == "__main__":
    unittest.main()
