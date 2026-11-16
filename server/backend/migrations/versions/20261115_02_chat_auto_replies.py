"""Persist auto-reply types; adopt known historical messages without editing them."""
from alembic import op
import sqlalchemy as sa

revision = '20261115_02'
down_revision = '20261115_01'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('chat_auto_replies',
        sa.Column('buyer', sa.String(32), sa.ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('kind', sa.String(16), primary_key=True),
        sa.Column('event', sa.String(24), primary_key=True),
        sa.Column('message_id', sa.String(32), nullable=False))
    # Text matching is confined to this one-time migration of pre-typed history.
    # MIN(id) selects one marker even when a previous release left duplicates.
    for event, text in (
        ('greeting', 'привет, что тебя беспокоит?'),
        ('first_ack', 'запрос передан менеджеру, ожидаем ответа, помним о бренности бытия'),
    ):
        op.get_bind().execute(sa.text('''
            INSERT INTO chat_auto_replies (buyer, kind, event, message_id)
            SELECT buyer, kind, :event, MIN(id) FROM buyer_messages
            WHERE staff = true AND text = :text
              AND kind IN ('support', 'cooperation', 'm_support', 'm_cooperation')
            GROUP BY buyer, kind
        '''), {'event': event, 'text': text})


def downgrade():
    raise RuntimeError('Auto-reply marker downgrade is disabled to prevent repeated messages')
