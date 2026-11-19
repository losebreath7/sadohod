"""Migration for moderator-initiated restrictions and durable notification queue."""
from alembic import op
import sqlalchemy as sa

revision = '20261119_09'
down_revision = '20261119_08'
branch_labels = None
depends_on = None


def upgrade():
    for table, key, target in (
        ('moderation_account_restrictions', 'buyer_id', 'buyers.id'),
        ('moderation_shop_restrictions', 'seller_id', 'sellers.id'),
    ):
        op.create_table(
            table,
            sa.Column(key, sa.String(32), sa.ForeignKey(target, ondelete='CASCADE'),
                      primary_key=True),
            sa.Column('active', sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column('reason', sa.Text(), nullable=False, server_default=''),
            sa.Column('until', sa.Float(), nullable=True),
            sa.Column('moderator_id', sa.String(32),
                      sa.ForeignKey('moderator_users.id'), nullable=False),
            sa.Column('updated_at', sa.Float(), nullable=False),
        )
    op.create_table(
        'moderation_email_outbox',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('recipient', sa.String(254), nullable=False),
        sa.Column('subject', sa.String(200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('status', sa.String(16), nullable=False, server_default='pending'),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('next_attempt_at', sa.Float(), nullable=False),
        sa.Column('created_at', sa.Float(), nullable=False),
        sa.Column('sent_at', sa.Float(), nullable=True),
    )
    op.create_index('ix_moderation_email_due', 'moderation_email_outbox',
                    ['status', 'next_attempt_at'])


def downgrade():
    raise RuntimeError('Moderation enforcement downgrade is disabled: preserve audit and email history')
