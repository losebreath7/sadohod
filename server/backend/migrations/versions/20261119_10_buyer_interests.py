"""Persist personal category interests without retaining individual view histories."""
from alembic import op
import sqlalchemy as sa

revision = '20261119_10'
down_revision = '20261119_09'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('buyer_category_interests',
        sa.Column('buyer_id', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'),
                  primary_key=True),
        sa.Column('category_id', sa.String(80), primary_key=True),
        sa.Column('day', sa.Integer(), primary_key=True),
        sa.Column('views', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.Float(), nullable=False))
    op.create_index('ix_buyer_interests_day', 'buyer_category_interests', ['day'])


def downgrade():
    raise RuntimeError('Recommendations downgrade is disabled to preserve user data')
