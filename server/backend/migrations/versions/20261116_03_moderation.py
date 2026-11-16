"""Add staff-only moderation accounts and review pre-publication state.

Existing reviews are grandfathered as approved. New reviews become pending.
No existing reviews, buyer data, merchandise or media are removed.
"""
from alembic import op
import sqlalchemy as sa

revision = '20261116_03'
down_revision = '20261115_02'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('moderator_users',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('username', sa.String(40), nullable=False),
        sa.Column('display_name', sa.String(80), nullable=False),
        sa.Column('secret_digest', sa.String(160), nullable=False),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.Float(), nullable=False),
        sa.UniqueConstraint('username'))
    op.create_index('ix_moderator_users_username', 'moderator_users', ['username'], unique=True)
    op.create_table('moderator_sessions',
        sa.Column('digest', sa.String(64), primary_key=True),
        sa.Column('moderator_id', sa.String(32), sa.ForeignKey('moderator_users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('expires_at', sa.Float(), nullable=False))
    op.create_index('ix_moderator_sessions_moderator_id', 'moderator_sessions', ['moderator_id'])
    op.create_table('moderation_actions',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('moderator_id', sa.String(32), sa.ForeignKey('moderator_users.id'), nullable=False),
        sa.Column('kind', sa.String(24), nullable=False),
        sa.Column('target_id', sa.String(32), nullable=False),
        sa.Column('decision', sa.String(24), nullable=False),
        sa.Column('note', sa.Text(), nullable=False, server_default=''),
        sa.Column('created_at', sa.Float(), nullable=False))
    op.create_index('ix_moderation_actions_moderator_id', 'moderation_actions', ['moderator_id'])

    # Preserve previously published reviews; only reviews submitted after this
    # migration enter moderation. The SQLAlchemy default for new rows is pending.
    op.add_column('seller_reviews_v082',
        sa.Column('moderation_status', sa.String(16), nullable=False,
                  server_default='approved'))
    op.add_column('seller_review_reports_v082',
        sa.Column('resolved_at', sa.Float(), nullable=False, server_default='0'))
    op.add_column('seller_review_reports_v082',
        sa.Column('resolution', sa.String(16), nullable=False, server_default=''))


def downgrade():
    raise RuntimeError('Moderation downgrade is disabled to preserve review and audit history')
