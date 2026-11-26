"""Runs only against the isolated Compose QA service (never the app database)."""
import os
import uuid

import pytest
import sqlalchemy as sa
from sqlalchemy.engine import make_url

from backend.app.config import DATABASE_URL
from backend.app.migrations import upgrade_database
from backend.app.migration_rehearsal import rehearse, snapshot
from backend.tests.test_migrations import populate_legacy, baseline, revision
from backend.tests.test_chat_auto_replies import run_concurrent_replies

pytestmark = pytest.mark.skipif(
    os.environ.get('SADOHOD_QA') != '1' or
    DATABASE_URL != 'postgresql+psycopg://qa:qa@qa-db:5432/sadohod_qa',
    reason='requires the dedicated compose.qa.yml database',
)


def test_postgres_legacy_copy_and_fresh_database():
    url = make_url(DATABASE_URL)
    admin = sa.create_engine(url, isolation_level='AUTOCOMMIT')
    names = ['sadohod_verify_' + uuid.uuid4().hex for _ in range(3)]
    engines = [sa.create_engine(url.set(database=name)) for name in names]
    source, copied, fresh = engines
    try:
        with admin.connect() as c:
            c.exec_driver_sql(f'CREATE DATABASE {names[0]} TEMPLATE template0')
            c.exec_driver_sql(f'CREATE DATABASE {names[2]} TEMPLATE template0')
        populate_legacy(source)
        with source.begin() as c:
            c.exec_driver_sql('CREATE EXTENSION vector')
            for ddl in baseline.VECTOR_DDL:
                c.exec_driver_sql(ddl)
            c.execute(sa.text('INSERT INTO product_image_vectors VALUES (:id, CAST(:v AS vector))'),
                      {'id':'image', 'v':str([0.1]*96)})
            c.execute(sa.text('INSERT INTO product_image_ml_vectors VALUES (:id, :model, CAST(:v AS vector))'),
                      {'id':'image', 'model':'fixture', 'v':str([0.1]*512)})
        before = snapshot(source)
        source.dispose()
        with admin.connect() as c:
            c.exec_driver_sql(f'CREATE DATABASE {names[1]} TEMPLATE {names[0]}')
        rehearse(copied)
        original_columns = {table: value[0] for table, value in before.items()}
        assert snapshot(copied, original_columns) == before
        assert snapshot(source) == before
        assert 'alembic_version' not in sa.inspect(source).get_table_names()
        assert revision(copied) == '20261126_18'
        run_concurrent_replies(copied)
        upgrade_database(fresh)
        assert revision(fresh) == '20261126_18'
        with fresh.connect() as c:
            baseline.validate_vectors(c, sa.inspect(c))
        # An invalid vector dimension must roll back the adoption completely.
        with source.begin() as c:
            c.exec_driver_sql('DROP INDEX product_image_vectors_hnsw')
            c.exec_driver_sql('DELETE FROM product_image_vectors')
            c.exec_driver_sql('ALTER TABLE product_image_vectors ALTER COLUMN embedding TYPE vector(3)')
        with pytest.raises(RuntimeError, match='Incompatible legacy vector table'):
            upgrade_database(source)
        assert 'alembic_version' not in sa.inspect(source).get_table_names()
    finally:
        for engine in engines:
            engine.dispose()
        with admin.connect() as c:
            for name in reversed(names):
                c.exec_driver_sql(f'DROP DATABASE IF EXISTS {name}')
        admin.dispose()
