import shutil
import re
import tempfile
import unittest
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


if __name__ == '__main__':
    unittest.main()
