import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

try:
    import yaml
except ImportError:
    yaml = None


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / 'ansible/roles/docker_swarm_secrets'


@unittest.skipUnless(yaml and shutil.which('ansible-playbook'), 'Ansible and PyYAML are required')
class BitwardenSecretsTest(unittest.TestCase):
    def run_role(self, fields, eligible=None, status='unlocked', check=False, sync_fails=False,
                 item_name='SG App secrets', definitions=None, get_error=''):
        definitions = definitions if definitions is not None else [
            {'name': 'registry_htpasswd', 'field': 'htpasswd'},
            {'name': 'database', 'field': 'db_password'},
            {'name': 'encoded', 'field': 'encoded_value', 'encoding': 'base64'},
            {'name': 'in_use', 'field': 'not_read'},
        ]
        if eligible is None:
            eligible = ['registry_htpasswd', 'database', 'encoded']
        excluded = {
            'Verify Docker Swarm manager availability',
            'Create the cluster command directory',
            'Install the Docker Swarm secrets creation script',
            'Select managed secrets that can be safely created or updated',
            'Explain secrets skipped because active services use them',
        }
        tasks = [task for task in yaml.safe_load((ROLE / 'tasks/main.yml').read_text())
                 if task['name'] not in excluded]
        for task in tasks:
            task['become'] = False
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            calls = temporary / 'calls.jsonl'
            values = temporary / 'values.jsonl'
            fixture = temporary / 'item.json'
            fixture.write_text(json.dumps({'id': 'fixture-item', 'name': item_name, 'fields': fields}))
            cli = temporary / 'bw'
            cli.write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['BW_TEST_CALLS'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
if args == ['--version']:
    print('test-cli')
elif args == ['status', '--nointeraction']:
    print(json.dumps({'status': os.environ['BW_TEST_STATUS']}))
elif args == ['sync', '--nointeraction']:
    sys.exit(1 if os.environ['BW_TEST_SYNC_FAILS'] == 'true' else 0)
elif args == ['get', 'item', 'SG App secrets', '--raw', '--nointeraction']:
    assert os.environ['BW_SESSION'] == 'fake-session'
    if os.environ['BW_TEST_GET_ERROR']:
        print(os.environ['BW_TEST_GET_ERROR'], file=sys.stderr)
        sys.exit(1)
    print(pathlib.Path(os.environ['BW_TEST_ITEM']).read_text())
else:
    sys.exit(2)
''')
            cli.chmod(0o755)
            helper = temporary / 'create-secret'
            helper.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
assert sys.argv[1] == '--apply'
with open(os.environ['BW_TEST_VALUES'], 'a') as stream:
    stream.write(json.dumps({'name': sys.argv[2], 'value': sys.stdin.read()}) + '\\n')
''')
            helper.chmod(0o755)
            playbook = temporary / 'playbook.yml'
            playbook.write_text(yaml.safe_dump([{
                'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                'vars': {
                    'ansible_python_interpreter': sys.executable,
                    'cluster_admin_user': 'fixture-user',
                    'ansible_remote_tmp': str(temporary / 'remote'),
                    'docker_swarm_secrets': definitions,
                    'docker_swarm_secrets_bitwarden_item': 'SG App secrets',
                    'docker_swarm_secrets_bitwarden_cli': str(cli),
                    'docker_swarm_secrets_script': str(helper),
                    'docker_swarm_secrets_eligible': {'stdout_lines': eligible},
                },
                'tasks': tasks,
            }], sort_keys=False))
            environment = dict(os.environ, ANSIBLE_LOCAL_TEMP=str(temporary / 'local'),
                               ANSIBLE_NOCOLOR='1', BW_SESSION='fake-session',
                               BW_TEST_CALLS=str(calls), BW_TEST_VALUES=str(values),
                               BW_TEST_ITEM=str(fixture), BW_TEST_STATUS=status,
                               BW_TEST_SYNC_FAILS=str(sync_fails).lower(), BW_TEST_GET_ERROR=get_error)
            command = ['ansible-playbook', '-i', 'localhost,', str(playbook)]
            if check:
                command.append('--check')
            result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=90)
            read_lines = lambda path: [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
            return result, read_lines(calls), read_lines(values)

    def valid_fields(self):
        return [
            {'name': 'htpasswd', 'value': 'fake-user:fake-hash'},
            {'name': 'db_password', 'value': 'test-secret-only\nwith newline\n'},
            {'name': 'encoded_value', 'value': base64.b64encode(b'{"fake": true}\n').decode()},
        ]

    def test_reads_one_item_and_preserves_field_aliases_newlines_and_base64(self):
        result, calls, values = self.run_role(self.valid_fields())
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual([
            ['--version'], ['status', '--nointeraction'], ['sync', '--nointeraction'],
            ['get', 'item', 'SG App secrets', '--raw', '--nointeraction'],
        ], calls)
        self.assertEqual([
            {'name': 'registry_htpasswd', 'value': 'fake-user:fake-hash'},
            {'name': 'database', 'value': 'test-secret-only\nwith newline\n'},
            {'name': 'encoded', 'value': '{"fake": true}\n'},
        ], values)
        self.assertNotIn('test-secret-only', result.stdout + result.stderr)
        self.assertNotIn('fake-session', result.stdout + result.stderr)

    def test_provisions_all_secrets_required_by_the_backend(self):
        definitions = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())['docker_swarm_secrets']
        managed = {definition['name'] for definition in definitions}
        stack = yaml.safe_load((ROOT / 'apps/stacks/application.yml').read_text())
        backend_secrets = stack['services']['backend']['secrets']
        required = {secret if isinstance(secret, str) else secret['source'] for secret in backend_secrets}
        self.assertFalse(required - managed, f'Backend secrets missing from Ansible: {required - managed}')

    def test_invalid_field_aborts_before_any_secret_is_changed(self):
        for invalid in ([], [{'name': 'db_password', 'value': ''}],
                        [{'name': 'db_password', 'value': None}],
                        [{'name': 'db_password', 'value': 'one'}, {'name': 'db_password', 'value': 'two'}]):
            with self.subTest(invalid=invalid):
                fields = [field for field in self.valid_fields() if field['name'] != 'db_password'] + invalid
                result, _, values = self.run_role(fields)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], values)
                self.assertNotIn('TASK [Create or update Docker Swarm secrets]', result.stdout)

    def test_locked_vault_and_failed_sync_never_read_or_apply_values(self):
        for options in ({'status': 'locked'}, {'sync_fails': True}):
            with self.subTest(options=options):
                result, calls, values = self.run_role(self.valid_fields(), **options)
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any(call[:2] == ['get', 'item'] for call in calls))
                self.assertEqual([], values)

    def test_cli_errors_are_explained_without_exposing_the_original_output(self):
        for error, expected in (
            ('More than one result was found. fake-private-vault-data', 'Nazwa pasuje do kilku wpisów'),
            ('Not found. fake-private-vault-data', 'Nie znaleziono wpisu'),
            ('Unknown error fake-private-vault-data', 'Sprawdź lokalną sesję bw'),
        ):
            with self.subTest(error=error):
                result, _, values = self.run_role(self.valid_fields(), get_error=error)
                self.assertNotEqual(0, result.returncode)
                self.assertIn(expected, result.stdout)
                self.assertNotIn('fake-private-vault-data', result.stdout + result.stderr)
                self.assertNotIn('TASK [Create or update Docker Swarm secrets]', result.stdout)
                self.assertEqual([], values)

    def test_partially_matching_item_name_is_rejected(self):
        result, _, values = self.run_role(self.valid_fields(), item_name='SG App secrets old')
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn('TASK [Create or update Docker Swarm secrets]', result.stdout)
        self.assertEqual([], values)

    def test_check_mode_and_all_secrets_in_use_do_not_open_the_vault(self):
        for options in ({'check': True}, {'eligible': []}):
            with self.subTest(options=options):
                result, calls, values = self.run_role([], **options)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertEqual([['--version']], calls)
                self.assertEqual([], values)

    def test_wrapper_discovers_bw_and_passes_session_without_command_line_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            binaries = temporary / 'bin'
            binaries.mkdir()
            cli = binaries / 'bw'
            cli.write_text('#!/usr/bin/env bash\nexit 0\n')
            cli.chmod(0o755)
            playbook = binaries / 'ansible-playbook'
            playbook.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
print(json.dumps({'argv': sys.argv[1:], 'cli': os.environ['BITWARDEN_CLI'],
                  'session': os.environ['BW_SESSION']}))
''')
            playbook.chmod(0o755)
            environment = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                               ANSIBLE_HOME_SSH_DIR=str(temporary), BW_SESSION='fake-session')
            for name in ('BITWARDEN_CLI', 'WSL_INTEROP'):
                environment.pop(name, None)
            result = subprocess.run(['bash', str(ROOT / 'ansible/06-docker-secrets.sh'), 'home', 'check',
                                     '-e', 'docker_swarm_secrets_bitwarden_item=fixture-uuid'],
                                    env=environment, capture_output=True, text=True, check=True)
            captured = json.loads(result.stdout)
            self.assertEqual(str(cli), captured['cli'])
            self.assertEqual('fake-session', captured['session'])
            self.assertNotIn('fake-session', captured['argv'])
            self.assertIn('--check', captured['argv'])
            self.assertIn('playbooks/docker-secrets.yml', captured['argv'])
            self.assertIn('docker_swarm_secrets_bitwarden_item=fixture-uuid', captured['argv'])


if __name__ == '__main__':
    unittest.main()
