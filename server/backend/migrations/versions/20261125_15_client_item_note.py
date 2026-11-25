from alembic import op
import sqlalchemy as sa

revision = '20261125_15'
down_revision = '20261124_14'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('sadohodets_folder_items',
                  sa.Column('note', sa.String(250), nullable=False, server_default=''))


def downgrade():
    raise RuntimeError('Client note downgrade is disabled')
