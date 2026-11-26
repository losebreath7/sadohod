"""Reversible private client folder archive."""
from alembic import op
import sqlalchemy as sa

revision = '20261126_18'
down_revision = '20261126_17'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('sadohodets_folders', sa.Column('archived', sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade():
    op.drop_column('sadohodets_folders', 'archived')
