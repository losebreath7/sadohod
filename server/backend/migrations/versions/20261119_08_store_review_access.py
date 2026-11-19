"""Explicit reviewer authentication credentials (no bypass for ordinary users)."""
from alembic import op
import sqlalchemy as sa

revision = '20261119_08'
down_revision = '20261117_07'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'store_review_access',
        sa.Column('email', sa.String(254), primary_key=True),
        sa.Column('code_digest', sa.String(128), nullable=False),
        sa.Column('platform', sa.String(16), nullable=False),
        sa.Column('role', sa.String(16), nullable=False),
        sa.Column('expires', sa.Float(), nullable=False),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('failed_total', sa.Integer(), nullable=False, server_default='0'),
    )


def downgrade():
    raise RuntimeError('Do not silently discard reviewer access and audit state')
