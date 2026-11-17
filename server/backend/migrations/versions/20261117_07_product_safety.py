"""Persistent product reports and staff takedown holds (additive)."""
from alembic import op
import sqlalchemy as sa

revision = '20261117_07'
down_revision = '20261117_06'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'product_reports',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('buyer_id', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), nullable=False),
        sa.Column('product_id', sa.String(32), sa.ForeignKey('products.id', ondelete='CASCADE'), nullable=False),
        sa.Column('reason', sa.String(200), nullable=False),
        sa.Column('created_at', sa.Float(), nullable=False),
        sa.Column('resolved_at', sa.Float(), nullable=False, server_default='0'),
        sa.Column('resolution', sa.String(16), nullable=False, server_default=''),
        sa.UniqueConstraint('buyer_id', 'product_id', name='uq_product_report_buyer_product'),
    )
    op.create_index('ix_product_reports_buyer_id', 'product_reports', ['buyer_id'])
    op.create_index('ix_product_reports_product_id', 'product_reports', ['product_id'])
    op.create_table(
        'product_safety_holds',
        sa.Column('product_id', sa.String(32), sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('reason', sa.Text(), nullable=False, server_default=''),
        sa.Column('moderator_id', sa.String(32), sa.ForeignKey('moderator_users.id'), nullable=False),
        sa.Column('updated_at', sa.Float(), nullable=False),
    )


def downgrade():
    raise RuntimeError('Product safety downgrade is disabled to protect reports and enforcement history')
