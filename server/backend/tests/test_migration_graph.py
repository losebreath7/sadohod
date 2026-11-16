"""Guards the Alembic revision graph against silent merge collisions.

Two branches can each add a migration file with the same revision id. Git sees
different file names and merges them without a conflict, but Alembic then has
two heads (or a duplicated id) and the API cannot start or upgrade a database.
"""
import re
import warnings
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory

VERSIONS = Path(__file__).resolve().parents[1] / 'migrations' / 'versions'


def script_directory() -> ScriptDirectory:
    config = Config()
    config.set_main_option('script_location', str(VERSIONS.parent))
    return ScriptDirectory.from_config(config)


def test_revision_ids_are_unique_across_files():
    seen: dict[str, str] = {}
    for path in sorted(VERSIONS.glob('*.py')):
        match = re.search(r"^revision\s*=\s*['\"]([^'\"]+)['\"]",
                          path.read_text(encoding='utf-8'), re.M)
        if not match:
            continue
        revision = match.group(1)
        assert revision not in seen, (
            f'Revision {revision} is defined in both {seen[revision]} and {path.name}')
        seen[revision] = path.name


def test_migrations_form_one_linear_chain():
    with warnings.catch_warnings():
        warnings.simplefilter('error')  # "present more than once" is a warning
        script = script_directory()
        heads = script.get_heads()
    assert len(heads) == 1, f'Several Alembic heads: {heads}'
    chain = [r.revision for r in script.walk_revisions()]
    assert len(chain) == len(set(chain))
    branched = [r.revision for r in script.walk_revisions() if len(r.nextrev) > 1]
    assert not branched, f'Branch points in the migration history: {branched}'
