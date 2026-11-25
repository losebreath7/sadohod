"""Private client contact link in courier folders."""
from alembic import op
import sqlalchemy as sa

revision = '20261125_16'
down_revision = '20261125_15'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('sadohodets_folders', sa.Column('client_link', sa.String(2048), nullable=False, server_default=''))


def downgrade():
    op.drop_column('sadohodets_folders', 'client_link')
