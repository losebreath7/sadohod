"""Add a stable category tree and product links without changing legacy products.

Existing category strings, offers, images and moderation history remain intact.
V1 tree rows are immutable stable IDs. Never remove them from an old migration.
"""
from alembic import op
import sqlalchemy as sa

revision = '20261117_06'
down_revision = '20261116_05'
branch_labels = None
depends_on = None


def upgrade():
    from backend.app.catalog_taxonomy import NODES_V1, LEGACY, resolve_leaf, path_ids
    categories = op.create_table(
        'catalog_categories',
        sa.Column('id', sa.String(64), primary_key=True),
        sa.Column('parent_id', sa.String(64),
                  sa.ForeignKey('catalog_categories.id'), nullable=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False))
    op.create_index('ix_catalog_categories_parent_id', 'catalog_categories', ['parent_id'])
    assignments = op.create_table(
        'product_category_assignments',
        sa.Column('product_id', sa.String(32),
                  sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('category_id', sa.String(64),
                  sa.ForeignKey('catalog_categories.id'), nullable=False),
        sa.Column('source', sa.String(24), nullable=False))
    op.create_index('ix_product_category_assignments_category_id',
                    'product_category_assignments', ['category_id'])

    op.bulk_insert(categories, [
        {'id': node_id, 'parent_id': parent_id, 'name': name, 'position': i}
        for i, (node_id, parent_id, name) in enumerate(NODES_V1)
    ])
    # Only backfill unambiguous legacy categories. Unknown titles keep their
    # original classification; published products are never taken offline.
    connection = op.get_bind()
    existing = connection.execute(sa.text(
        'SELECT id, title, category FROM products')).all()
    links = []
    for row in existing:
        leaf = resolve_leaf(row.title)
        legacy = LEGACY.get(row.category)
        if legacy and (leaf is None or legacy not in path_ids(leaf)):
            leaf = legacy
        if leaf:
            links.append({'product_id': row.id, 'category_id': leaf,
                          'source': 'backfill'})
    if links:
        op.bulk_insert(assignments, links)


def downgrade():
    raise RuntimeError('Category taxonomy downgrade is disabled to protect product links')
