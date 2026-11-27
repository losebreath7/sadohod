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
    # Existing public/previously approved products have no reliable first date.
    # Mark them as old, rather than granting a new-product boost after upgrade.
    op.execute(sa.text("""INSERT INTO feed_publications (product_id, published_at)
        SELECT p.id, 0 FROM products p
        WHERE EXISTS (SELECT 1 FROM offers o WHERE o.product_id = p.id)
          AND NOT EXISTS (SELECT 1 FROM product_details d WHERE d.product_id = p.id AND d.active = false)
        OR EXISTS (SELECT 1 FROM merchant_products m WHERE m.product_id = p.id AND m.status = 'approved')"""))


def downgrade():
    op.drop_table('feed_daily_views')
    op.drop_table('feed_publications')
