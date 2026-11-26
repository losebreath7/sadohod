"""Persist item quantities; existing collection entries start at one."""
from alembic import op
import sqlalchemy as sa

revision = '20261126_17'
down_revision = '20261125_16'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('sadohodets_folder_items') as batch:
        batch.add_column(sa.Column('quantity', sa.Integer(), nullable=False, server_default='1'))
        batch.create_check_constraint('ck_sadohodets_item_quantity', 'quantity >= 1 AND quantity <= 999')


def downgrade():
    with op.batch_alter_table('sadohodets_folder_items') as batch:
        batch.drop_constraint('ck_sadohodets_item_quantity', type_='check')
        batch.drop_column('quantity')
