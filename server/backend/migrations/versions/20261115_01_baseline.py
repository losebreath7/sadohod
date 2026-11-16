"""Adopt the R3 schema only after checking existing tables. Never blind-stamp."""
import sqlalchemy as sa
from alembic import op
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from backend.migrations.baseline_r3 import metadata

revision = '20261115_01'
down_revision = None
branch_labels = None
depends_on = None

VECTOR_DDL = (
    '''CREATE TABLE IF NOT EXISTS product_image_vectors (
        image_id VARCHAR(32) PRIMARY KEY REFERENCES product_images(id) ON DELETE CASCADE,
        embedding vector(96) NOT NULL)''',
    '''CREATE TABLE IF NOT EXISTS product_image_ml_vectors (
        image_id VARCHAR(32) REFERENCES product_images(id) ON DELETE CASCADE,
        model_id VARCHAR(140) NOT NULL, embedding vector(512) NOT NULL,
        PRIMARY KEY (image_id, model_id))''',
    '''CREATE INDEX IF NOT EXISTS product_image_vectors_hnsw
        ON product_image_vectors USING hnsw (embedding vector_cosine_ops)''',
    '''CREATE INDEX IF NOT EXISTS product_image_ml_vectors_hnsw
        ON product_image_ml_vectors USING hnsw (embedding vector_cosine_ops)''',
)


def validate_vectors(connection, inspector):
    for table, dimension, pk in (
        ('product_image_vectors', 96, ['image_id']),
        ('product_image_ml_vectors', 512, ['image_id', 'model_id']),
    ):
        if not inspector.has_table(table):
            continue
        actual = {r[0]: (r[1], r[2]) for r in connection.execute(sa.text('''
            SELECT a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull
            FROM pg_attribute a WHERE a.attrelid = to_regclass(:table)
            AND a.attnum > 0 AND NOT a.attisdropped'''), {'table': table})}
        expected = {'image_id': ('character varying(32)', True),
                    'embedding': (f'vector({dimension})', True)}
        if len(pk) == 2:
            expected['model_id'] = ('character varying(140)', True)
        if actual != expected or inspector.get_pk_constraint(table)['constrained_columns'] != pk:
            raise RuntimeError(f'Incompatible legacy vector table: {table}')
        fks = inspector.get_foreign_keys(table)
        if not any(f['constrained_columns'] == ['image_id'] and
                   f['referred_table'] == 'product_images' and
                   f['referred_columns'] == ['id'] and
                   f['options'].get('ondelete') == 'CASCADE' for f in fks):
            raise RuntimeError(f'Incompatible vector foreign key: {table}')
        definition = connection.scalar(sa.text('SELECT pg_get_indexdef(to_regclass(:name))'),
                                       {'name': table + '_hnsw'})
        if definition is not None and (
            f'ON public.{table} USING hnsw (embedding vector_cosine_ops)' not in definition
        ):
            raise RuntimeError(f'Incompatible vector index: {table}')


def upgrade():
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    # Permit absent tables/indexes (older additive releases), but never rewrite
    # existing columns, constraints or application data automatically.
    def include_object(obj, name, type_, reflected, compare_to):
        return not (type_ == 'table' and reflected and name not in metadata.tables)
    ctx = MigrationContext.configure(connection, opts={
        'compare_type': True, 'compare_server_default': True,
        'include_object': include_object,
    })
    differences = compare_metadata(ctx, metadata)
    expected_indexes = {index.name for table in metadata.tables.values() for index in table.indexes}
    incompatible = [d for d in differences if not (
        isinstance(d, tuple) and (d[0] in {'add_table', 'add_index'} or
            (d[0] == 'remove_index' and d[1].name not in expected_indexes))
    )]
    for table in metadata.sorted_tables:
        if inspector.has_table(table.name):
            expected = [c.name for c in table.primary_key.columns]
            if inspector.get_pk_constraint(table.name)['constrained_columns'] != expected:
                incompatible.append(('primary_key', table.name))
    if incompatible:
        # No row values, connection URLs or secrets in diagnostics.
        raise RuntimeError('Existing database differs from the R3 baseline; '
                           'migration stopped. Schema differences: ' + repr(incompatible))
    if connection.dialect.name == 'postgresql':
        validate_vectors(connection, inspector)
        connection.execute(sa.text('CREATE EXTENSION IF NOT EXISTS vector'))
    metadata.create_all(connection)
    for table in metadata.sorted_tables:
        for index in table.indexes:
            index.create(connection, checkfirst=True)
    if connection.dialect.name == 'postgresql':
        for statement in VECTOR_DDL:
            connection.execute(sa.text(statement))


def downgrade():
    raise RuntimeError('Baseline downgrade is disabled to protect existing data; restore a verified backup instead')
