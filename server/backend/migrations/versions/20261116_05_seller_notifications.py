"""Add persistent seller notification inbox; preserve all existing records."""
from alembic import op
import sqlalchemy as sa

revision = '20261116_05'
down_revision = '20261116_04'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'merchant_notifications',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('buyer_id', sa.String(32),
                  sa.ForeignKey('buyers.id', ondelete='CASCADE'), nullable=False),
        sa.Column('event_type', sa.String(32), nullable=False),
        sa.Column('target_id', sa.String(32), nullable=False),
        sa.Column('title', sa.String(160), nullable=False),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('note', sa.Text(), nullable=False, server_default=''),
        sa.Column('created_at', sa.Float(), nullable=False),
        sa.Column('read_at', sa.Float(), nullable=True),
    )
    op.create_index('ix_merchant_notifications_buyer_id',
                    'merchant_notifications', ['buyer_id'])


def downgrade():
    raise RuntimeError('Seller notification downgrade is disabled to protect history')
