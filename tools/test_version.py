import shutil
import re
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import package_release
from pathlib import Path
from sync_version import ROOT, sync


class VersionChecks(unittest.TestCase):
    def test_checked_in_versions(self):
        sync(check=True)

    def test_stale_client_is_rejected_and_can_be_regenerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copy(ROOT / 'RELEASE.json', root / 'RELEASE.json')
            for name in ('buyer_app', 'seller_app', 'shared/flutter_core'):
                (root / name).mkdir(parents=True)
                shutil.copy(ROOT / name / 'pubspec.yaml', root / name / 'pubspec.yaml')
            sync(root)
            target = root / 'seller_app/pubspec.yaml'
            target.write_text(re.sub(r'^version:.*$', 'version: 0.0.0+1', target.read_text(), flags=re.M))
            before = target.read_bytes()
            with self.assertRaisesRegex(ValueError, 'seller_app/pubspec.yaml'):
                sync(root, check=True)
            self.assertEqual(target.read_bytes(), before)
            sync(root)
            sync(root, check=True)


class ReleaseEnvSecurityChecks(unittest.TestCase):
    def _package(self, names):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'tools').mkdir()
            (root / 'tools/release_files.txt').write_text('\\n'.join(names) + '\\n', encoding='utf-8')
            for name in names:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('TEMPLATE_ONLY=1\\n', encoding='utf-8')
            output = root / 'release.zip'
            with patch.object(package_release, 'ROOT', root):
                package_release.build(output)
            with ZipFile(output) as archive:
                return archive.namelist()

    def test_allow_only_reviewed_env_examples(self):
        names = ['.env.example', '.env.public.example']
        self.assertEqual(
            sorted(self._package(names)),
            sorted(['SADOHOD/' + name for name in names] +
                   ['SADOHOD/docs/FILE_MANIFEST_SHA256.json']),
        )

    def test_reject_real_env_and_env_lookalikes(self):
        for name in ('.env', '.env.public', '.env.production', '.env.local',
                     '.env.example.secret', 'server/.env',
                     'nested/.env.public.example'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Invalid release member'):
                self._package([name])


if __name__ == '__main__':
    unittest.main()
