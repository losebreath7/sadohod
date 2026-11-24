"""Add independent courier profiles, private folders and reviews."""
from alembic import op
import sqlalchemy as sa

revision = '20261124_12'
down_revision = '20261120_11'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'sadohodets_profiles',
        sa.Column('buyer_id', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('name', sa.String(120), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('contacts', sa.JSON(), nullable=False),
        sa.Column('avatar', sa.String(500), nullable=True),
        sa.Column('cover', sa.String(500), nullable=True),
        sa.Column('published', sa.Boolean(), nullable=False),
        sa.Column('last_active_at', sa.Float(), nullable=False),
        sa.Column('created_at', sa.Float(), nullable=False),
    )
    op.create_index('ix_sadohodets_directory', 'sadohodets_profiles', ['published', 'last_active_at'])
    op.create_table(
        'sadohodets_folders',
        sa.Column('id', sa.String(32), primary_key=True),
        sa.Column('owner_id', sa.String(32), sa.ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(120), nullable=False),
        sa.Column('note', sa.Text(), nullable=False),
        sa.Column('created_at', sa.Float(), nullable=False),
    )
    op.create_index('ix_sadohodets_folders_owner_id', 'sadohodets_folders', ['owner_id'])
    op.create_table(
        'sadohodets_folder_items',
        sa.Column('folder_id', sa.String(32), sa.ForeignKey('sadohodets_folders.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('product_id', sa.String(32), sa.ForeignKey('products.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('collected', sa.Boolean(), nullable=False),
        sa.Column('added_at', sa.Float(), nullable=False),
    )
    op.create_table(
        'sadohodets_reviews',
        sa.Column('profile_id', sa.String(32), sa.ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), primary_key=True),
        sa.Column('reviewer_id', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('rating', sa.Integer(), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('created_at', sa.Float(), nullable=False),
        sa.CheckConstraint('rating >= 1 AND rating <= 5', name='ck_sadohodets_review_rating'),
        sa.CheckConstraint('profile_id <> reviewer_id', name='ck_sadohodets_review_not_self'),
    )


def downgrade():
    raise RuntimeError('Courier downgrade is disabled to protect user data')
