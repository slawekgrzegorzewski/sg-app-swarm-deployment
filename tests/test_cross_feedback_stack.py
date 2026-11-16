import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class CrossFeedbackStackTest(unittest.TestCase):
    def test_application_uses_only_its_standard_stack(self):
        script = Path(__file__).resolve().parents[1] / 'apps/tools/start-stack.sh'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            release = root / 'releases/test-release'
            (release / 'stacks').mkdir(parents=True)
            (release / 'stacks/application.yml').touch()
            (root / 'current').symlink_to(release, target_is_directory=True)
            (root / 'observability.env').write_text('LOGGING_SYSLOG_ADDRESS=tcp://localhost:1514\n')
            binaries = root / 'bin'
            binaries.mkdir()
            docker = binaries / 'docker'
            docker.write_text('''#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ['CALLS_FILE'], 'a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
''')
            docker.chmod(0o755)
            calls_file = root / 'calls.jsonl'
            environment = dict(os.environ, CLUSTER_ROOT=str(root),
                               PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                               CALLS_FILE=str(calls_file))
            subprocess.run(['bash', str(script), 'application'], env=environment, check=True,
                           capture_output=True, text=True)
            calls = [json.loads(line) for line in calls_file.read_text().splitlines()]
            for operation in ('config', 'deploy'):
                command, = [call for call in calls if call[:2] == ['stack', operation]]
                self.assertIn(str(release / 'stacks/application.yml'), command)
                self.assertEqual(1, command.count('--compose-file'))
            self.assertFalse(any(call[:2] == ['service', 'update'] for call in calls))
            self.assertFalse(any(call[:2] == ['secret', 'inspect'] for call in calls))


if __name__ == '__main__':
    unittest.main()
