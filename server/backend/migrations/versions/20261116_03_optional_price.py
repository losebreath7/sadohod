"""Allow an unspecified price without changing any existing offer values."""
from alembic import op
import sqlalchemy as sa

revision = '20261116_03'
down_revision = '20261115_02'
branch_labels = None
depends_on = None


def upgrade():
    for table in ('offers', 'merchant_listings'):
        with op.batch_alter_table(table) as batch:
            batch.alter_column('price', existing_type=sa.Integer(), nullable=True)


def downgrade():
    raise RuntimeError('Price downgrade is disabled to preserve unspecified prices')
