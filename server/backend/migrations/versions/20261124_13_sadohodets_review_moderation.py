"""Moderate Sadohodets reviews before public display."""
from alembic import op
import sqlalchemy as sa

revision = '20261124_13'
down_revision = '20261124_12'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('sadohodets_reviews', sa.Column('moderation_status', sa.String(16), nullable=False, server_default='pending'))
    op.create_index('ix_sadohodets_reviews_status', 'sadohodets_reviews', ['moderation_status'])


def downgrade():
    raise RuntimeError('Review moderation downgrade is disabled')
