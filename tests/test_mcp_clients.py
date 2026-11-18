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
    def test_both_realms_define_separate_audience_mappers(self):
        for realm in ("sg", "sg-test"):
            for client in CLIENTS.load_clients(realm):
                mappers = {item["name"]: item for item in client["protocolMappers"]}
                mcp = mappers["MCP resource audience"]["config"]
                accountant = mappers["Accountant API audience"]["config"]
                self.assertNotIn("included.client.audience", mcp)
                self.assertEqual("https://mcp.grzegorzewski.pl/mcp", mcp["included.custom.audience"])
                self.assertEqual("sg-api", accountant["included.client.audience"])
                self.assertNotIn("included.custom.audience", accountant)

    def test_sync_repairs_legacy_mapper_and_adds_accountant_without_changing_other_options(self):
        client = CLIENTS.load_clients("sg")[0]
        mapper = copy.deepcopy(client["protocolMappers"][0])
        mapper["id"] = "mapper-id"
        mapper["config"].update({"included.client.audience": "sg-api", "existing-option": "keep"})
        original = copy.deepcopy(mapper)
        with patch.object(CLIENTS, "api_request", side_effect=[[mapper], None, None]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(3, api.call_count)
        update, create = api.call_args_list[1:]
        self.assertEqual("https://example/clients/client-id/protocol-mappers/models/mapper-id", update.args[1])
        self.assertEqual({"method": "PUT"}, update.kwargs)
        updated = update.args[3]
        expected = copy.deepcopy(original)
        expected["config"].pop("included.client.audience")
        self.assertEqual(expected, updated)
        self.assertEqual(client["protocolMappers"][1], create.args[3])
        self.assertEqual({}, create.kwargs)
        self.assertEqual(original, mapper)

    def test_sync_adds_only_accountant_to_existing_correct_mcp_mapper(self):
        client = CLIENTS.load_clients("sg")[0]
        with patch.object(CLIENTS, "api_request", side_effect=[[client["protocolMappers"][0]], None]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(2, api.call_count)
        self.assertEqual("Accountant API audience", api.call_args.args[3]["name"])

    def test_sync_is_idempotent(self):
        client = CLIENTS.load_clients("sg")[0]
        with patch.object(CLIENTS, "api_request", return_value=client["protocolMappers"]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(1, api.call_count)

    def test_preflights_both_mappers_before_any_write(self):
        client = CLIENTS.load_clients("sg")[0]
        legacy = copy.deepcopy(client["protocolMappers"][0])
        legacy["id"] = "legacy-mapper-id"
        legacy["config"]["included.client.audience"] = "sg-api"
        wrong_accountant = dict(client["protocolMappers"][1], protocolMapper="unexpected")
        for response in ([legacy, legacy], [legacy, wrong_accountant],
                         [dict(legacy, protocolMapper="unexpected")]):
            with patch.object(CLIENTS, "api_request", return_value=response) as api:
                with self.assertRaises(ValueError):
                    CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
            self.assertEqual(1, api.call_count)

    def test_preserves_mappers_with_unexpected_audiences(self):
        client = CLIENTS.load_clients("sg")[0]
        for key in ("included.client.audience", "included.custom.audience"):
            current = copy.deepcopy(client["protocolMappers"][0])
            current["config"][key] = "another-api"
            with patch.object(CLIENTS, "api_request", return_value=[current]) as api:
                with self.assertRaises(ValueError):
                    CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
            self.assertEqual(1, api.call_count)

    def test_creates_both_missing_mappers(self):
        client = CLIENTS.load_clients("sg")[0]
        with patch.object(CLIENTS, "api_request", side_effect=[[], None, None]) as api:
            CLIENTS.sync_audience_mapper(None, "https://example/clients", "fake-token", client, {"id": "client-id"})
        self.assertEqual(3, api.call_count)
        self.assertEqual(client["protocolMappers"], [call.args[3] for call in api.call_args_list[1:]])


if __name__ == "__main__":
    unittest.main()
