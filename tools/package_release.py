"""Build and verify a source distribution using a reviewed file list."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'docs/FILE_MANIFEST_SHA256.json'
PREFIX = 'SADOHOD/'


def build(output):
    from sync_version import sync
    sync(check=True)
    paths = (ROOT / 'tools/release_files.txt').read_text(encoding='utf-8').splitlines()
    if len(set(paths)) != len(paths) or MANIFEST in paths:
        raise ValueError('Invalid release list')
    hashes = {}
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as handle:
        temp = Path(handle.name)
    try:
        with ZipFile(temp, 'w', ZIP_DEFLATED, compresslevel=9) as archive:
            for name in paths:
                path = PurePosixPath(name)
                blocked = {'state', 'backups', 'uploads', '.git', '.pytest_cache', '__pycache__', 'mobile_demo', '.dart_tool'}
                if (not name or path.is_absolute() or '..' in path.parts or '\\' in name
                        or blocked.intersection(path.parts) or path.suffix in {'.pyc', '.dump'}
                        or (path.name.startswith('.env') and name != '.env.example')
                        or path.name == 'admin-token.txt'):
                    raise ValueError(f'Invalid release member: {name}')
                local = (ROOT / path).resolve()
                if ROOT not in local.parents or not local.is_file():
                    raise ValueError(f'Missing source: {name}')
                data = local.read_bytes()
                hashes[name] = hashlib.sha256(data).hexdigest()
                archive.writestr(PREFIX + name, data)
            archive.writestr(PREFIX + MANIFEST, json.dumps(hashes, ensure_ascii=False, indent=2) + '\n')
        with ZipFile(temp) as archive:
            expected = json.loads(archive.read(PREFIX + MANIFEST))
            names = [PREFIX + name for name in expected] + [PREFIX + MANIFEST]
            if sorted(archive.namelist()) != sorted(names):
                raise ValueError('Unexpected ZIP inventory')
            for name, digest in expected.items():
                if hashlib.sha256(archive.read(PREFIX + name)).hexdigest() != digest:
                    raise ValueError(f'Hash mismatch: {name}')
        os.replace(temp, output)
    finally:
        temp.unlink(missing_ok=True)
    print(f'{len(hashes)} verified files plus manifest: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    build(parser.parse_args().output.resolve())
