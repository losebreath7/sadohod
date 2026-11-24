"""Separate binary profile media from public directory payload."""
from alembic import op
import sqlalchemy as sa

revision = '20261124_14'
down_revision = '20261124_13'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('sadohodets_media',
        sa.Column('profile_id', sa.String(32), sa.ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), primary_key=True),
        sa.Column('kind', sa.String(8), primary_key=True),
        sa.Column('raw', sa.LargeBinary(), nullable=False))


def downgrade():
    raise RuntimeError('Media downgrade is disabled')
