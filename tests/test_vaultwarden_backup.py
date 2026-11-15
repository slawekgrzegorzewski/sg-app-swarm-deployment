from pathlib import Path
import runpy
import sqlite3
import tarfile
import tempfile
import unittest


backup = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / 'ansible/playbooks/templates/backup_vaultwarden.py.j2')
)['backup']


class VaultwardenBackupTest(unittest.TestCase):
    def test_restores_committed_wal_data_and_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = root / 'data'
            backups = root / 'backups'
            data.mkdir()
            backups.mkdir()
            (data / 'attachments').mkdir()
            (data / 'attachments/attachment').write_bytes(b'encrypted attachment')
            (data / 'rsa_key.pem').write_text('test key')
            (data / 'config.json').write_text('{}')
            (data / 'icon_cache').mkdir()
            (data / 'icon_cache/icon').write_bytes(b'icon')

            with sqlite3.connect(data / 'db.sqlite3') as source:
                source.execute('PRAGMA journal_mode=WAL')
                source.execute('CREATE TABLE items (value TEXT)')
                source.execute("INSERT INTO items VALUES ('encrypted item')")
                source.commit()
                backup(data, backups)

            archive_path, = backups.iterdir()
            self.assertEqual(archive_path.stat().st_mode & 0o777, 0o600)
            with tarfile.open(archive_path) as archive:
                self.assertEqual(
                    set(archive.getnames()),
                    {'db.sqlite3', 'attachments', 'attachments/attachment', 'rsa_key.pem', 'config.json'},
                )
                self.assertEqual(archive.extractfile('attachments/attachment').read(), b'encrypted attachment')
                restored_database = root / 'restored.sqlite3'
                restored_database.write_bytes(archive.extractfile('db.sqlite3').read())
            with sqlite3.connect(restored_database) as restored:
                self.assertEqual(restored.execute('SELECT value FROM items').fetchall(), [('encrypted item',)])
                self.assertEqual(restored.execute('PRAGMA integrity_check').fetchone(), ('ok',))

    def test_missing_database_does_not_create_an_empty_backup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(FileNotFoundError):
                backup(root, root)
            self.assertEqual(list(root.iterdir()), [])

    def test_corrupted_database_does_not_publish_an_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            database = root / 'db.sqlite3'
            database.write_bytes(b'corrupted database')
            with self.assertRaises(sqlite3.DatabaseError):
                backup(root, root)
            self.assertEqual(list(root.iterdir()), [database])


if __name__ == '__main__':
    unittest.main()
