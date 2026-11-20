"""Searchable product facets; existing primary category and publications untouched."""
from alembic import op
import sqlalchemy as sa

revision = '20261120_11'
down_revision = '20261119_10'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'product_search_tags',
        sa.Column('product_id', sa.String(32),
                  sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('tag', sa.String(80), primary_key=True),
        sa.Column('source', sa.String(24), nullable=False),
    )
    op.create_index('ix_product_search_tags_tag', 'product_search_tags', ['tag'])


def downgrade():
    raise RuntimeError('Product-search facet downgrade is disabled to protect indexed data')
