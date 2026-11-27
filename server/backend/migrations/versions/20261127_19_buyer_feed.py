"""Add first-publication metadata and daily deduplicated product views."""
from alembic import op
import sqlalchemy as sa

revision = '20261127_19'
down_revision = '20261126_18'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('feed_publications',
        sa.Column('product_id', sa.String(32), sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('published_at', sa.Float(), nullable=False))
    op.create_table('feed_daily_views',
        sa.Column('buyer_id', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('product_id', sa.String(32), sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('day', sa.Integer(), primary_key=True),
        sa.Column('engaged', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_index('ix_feed_views_day', 'feed_daily_views', ['day'])
    op.create_index('ix_feed_views_product', 'feed_daily_views', ['product_id'])


def downgrade():
    op.drop_table('feed_daily_views')
    op.drop_table('feed_publications')
