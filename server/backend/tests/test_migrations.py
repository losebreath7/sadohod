"""Migration checks on fresh databases and copies of the pre-Alembic schema."""
import importlib
import shutil

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext

from backend.app.database import Base
from backend.app.migrations import upgrade_database, migration_config
from backend.migrations.baseline_r3 import metadata

baseline = importlib.import_module('backend.migrations.versions.20261115_01_baseline')


def populate_legacy(engine):
    """R3 schema with real relationships and a binary attachment, no revision table."""
    metadata.create_all(engine)
    with engine.begin() as c:
        c.execute(metadata.tables['pavilions'].insert(), {'id':'pav', 'code':'82', 'zone':'Б-2В'})
        c.execute(metadata.tables['sellers'].insert(), {'id':'seller', 'name':'Анна', 'pavilion_id':'pav'})
        c.execute(metadata.tables['products'].insert(), {'id':'product', 'title':'Сумка',
            'category':'Сумки', 'description':'Тест', 'colors':['red'], 'is_demo':False})
        c.execute(metadata.tables['product_images'].insert(), {'id':'image', 'product_id':'product',
            'filename':'uploads/existing.jpg', 'descriptor':[0.1]*96})
        c.execute(metadata.tables['offers'].insert(), {'id':'offer', 'product_id':'product',
            'seller_id':'seller', 'pavilion_id':'pav', 'price':2500})
        # Use reflected required fields to make the fixture explicit and independent of ORM defaults.
        c.execute(metadata.tables['buyers'].insert(), {'id':'buyer', 'email':'test@example.com',
            'name':'Покупатель'})
        c.execute(metadata.tables['buyer_messages'].insert(), {'id':'message', 'buyer':'buyer',
            'kind':'support', 'text':'Фото', 'sent':2.0, 'staff':False})
        c.execute(metadata.tables['buyer_chat_attachments_v083'].insert(), {'id':'attachment',
            'buyer':'buyer', 'message_id':'message', 'filename':'photo.jpg',
            'mime':'image/jpeg', 'raw':b'\xff\xd8\x00test\xff\xd9', 'preview':'dGh1bWI='})


def contents(engine):
    with engine.connect() as c:
        return {t.name: [tuple(row) for row in c.execute(sa.select(t))]
                for t in metadata.sorted_tables if sa.inspect(c).has_table(t.name)}


def revision(engine):
    with engine.connect() as c:
        return c.scalar(sa.text('SELECT version_num FROM alembic_version'))


def test_fresh_database_matches_models_and_repeat_is_noop():
    engine = sa.create_engine('sqlite://')
    upgrade_database(engine)
    assert revision(engine) == '20261124_14'
    with engine.connect() as c:
        assert compare_metadata(MigrationContext.configure(c), Base.metadata) == []
    before = contents(engine)
    upgrade_database(engine)
    assert contents(engine) == before


def test_copy_of_existing_database_preserves_every_row(tmp_path):
    original = tmp_path / 'r3.db'
    source = sa.create_engine('sqlite:///' + str(original))
    populate_legacy(source)
    before = contents(source)
    source.dispose()
    copied = tmp_path / 'r4.db'
    shutil.copy2(original, copied)
    target = sa.create_engine('sqlite:///' + str(copied))
    upgrade_database(target)
    upgrade_database(target)
    assert contents(target) == before
    assert 'alembic_version' not in sa.inspect(source).get_table_names()
    assert contents(source) == before
    assert revision(target) == '20261124_14'


@pytest.mark.parametrize('change', [
    'ALTER TABLE products RENAME COLUMN title TO unexpected',
    'DROP INDEX ix_products_title; CREATE UNIQUE INDEX ix_products_title ON products (title)',
])
def test_incompatible_schema_rolls_back_without_stamping(change):
    engine = sa.create_engine('sqlite://')
    populate_legacy(engine)
    with engine.begin() as c:
        for sql in change.split(';'):
            c.exec_driver_sql(sql)
    with pytest.raises(RuntimeError, match='differs from the R3 baseline'):
        upgrade_database(engine)
    assert 'alembic_version' not in sa.inspect(engine).get_table_names()
    with engine.connect() as c:
        assert c.scalar(sa.text('SELECT count(*) FROM products')) == 1


def test_older_partial_schema_adds_missing_tables_and_indexes():
    engine = sa.create_engine('sqlite://')
    metadata.tables['pavilions'].create(engine)
    with engine.begin() as c:
        c.execute(metadata.tables['pavilions'].insert(), {'id':'keep', 'code':'81', 'zone':'Б'})
    upgrade_database(engine)
    assert revision(engine) == '20261124_14'
    with engine.connect() as c:
        assert c.scalar(sa.text('SELECT code FROM pavilions')) == '81'
    assert len(sa.inspect(engine).get_table_names()) == len(Base.metadata.tables) + 1


def test_concurrent_startup_serializes_migrations(tmp_path):
    engine = sa.create_engine('sqlite:///' + str(tmp_path / 'parallel.db'))
    # Alembic's proxy is process-local, just like separate API workers.
    import os
    import subprocess
    import sys
    env = dict(os.environ, DATABASE_URL=str(engine.url))
    processes = [subprocess.Popen([sys.executable, '-m', 'backend.app.migrations'],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
    for process in processes:
        out, err = process.communicate(timeout=30)
        assert process.returncode == 0, (out, err)
    assert revision(engine) == '20261124_14'


def test_baseline_downgrade_refuses_to_delete_data():
    engine = sa.create_engine('sqlite://')
    populate_legacy(engine)
    before = contents(engine)
    upgrade_database(engine)
    config = migration_config()
    with engine.connect() as c:
        config.attributes['connection'] = c
        with pytest.raises(RuntimeError, match='downgrade is disabled'):
            command.downgrade(config, 'base')
    assert contents(engine) == before
    assert revision(engine) == '20261124_14'


def test_existing_published_reviews_stay_visible_after_moderation_migration():
    engine = sa.create_engine('sqlite://')
    populate_legacy(engine)
    with engine.begin() as c:
        c.execute(metadata.tables['seller_reviews_v082'].insert(), {
            'id': 'original-review', 'buyer': 'buyer', 'seller': 'seller',
            'rating': 5, 'text': 'Старый опубликованный отзыв',
            'photos': [], 'hidden': False, 'reply': 'Спасибо!',
            'created_at': 100.0, 'updated_at': 100.0,
        })
    upgrade_database(engine)
    with engine.connect() as c:
        values = c.execute(sa.text(
            'SELECT moderation_status, text, reply, rating '
            'FROM seller_reviews_v082 WHERE id=:id'),
            {'id':'original-review'}).one()
        assert tuple(values) == (
            'approved', 'Старый опубликованный отзыв', 'Спасибо!', 5)
    engine.dispose()
