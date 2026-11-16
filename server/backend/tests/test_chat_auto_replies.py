from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session
from alembic import command

from backend.app.buyer_extras import BuyerMessage, ChatAutoReply, AUTO_REPLY_TEXT, create_auto_reply
from backend.app.account import Buyer
from backend.app.migrations import upgrade_database, migration_config
from backend.migrations.baseline_r3 import metadata
from backend.tests.test_account import setup, login


@pytest.mark.parametrize('kind', ['support', 'cooperation', 'm_support', 'm_cooperation'])
def test_text_change_cannot_resend_existing_type(tmp_path, monkeypatch, kind):
    engine = sa.create_engine('sqlite:///' + str(tmp_path / 'chat.db'))
    upgrade_database(engine)
    with Session(engine) as db:
        db.add(Buyer(id='buyer', email='buyer@example.com', name=''))
        db.commit()
        for event in ('greeting', 'first_ack'):
            assert create_auto_reply(db, 'buyer', kind, event)
        db.commit()
        for event in ('greeting', 'first_ack'):
            monkeypatch.setitem(AUTO_REPLY_TEXT, event, 'Updated wording')
            assert not create_auto_reply(db, 'buyer', kind, event)
        db.commit()
        assert db.scalar(sa.select(sa.func.count()).select_from(BuyerMessage)) == 2


def test_migration_adopts_old_messages_preserving_duplicates():
    engine = sa.create_engine('sqlite://')
    metadata.create_all(engine)
    config = migration_config()
    with engine.connect() as connection:
        config.attributes['connection'] = connection
        command.upgrade(config, '20261115_01')
    with Session(engine) as db:
        db.add(Buyer(id='buyer', email='old@example.com', name=''))
        db.flush()
        for kind in ('support', 'cooperation', 'm_support', 'm_cooperation'):
            for event, text in AUTO_REPLY_TEXT.items():
                for i in range(2):
                    db.add(BuyerMessage(id=f'{kind}-{event}-{i}', buyer='buyer', kind=kind,
                        text=text, sent=float(i), staff=True))
        db.add(BuyerMessage(id='human', buyer='buyer', kind='support', text='Manual reply', sent=4., staff=True))
        db.commit()
    upgrade_database(engine)
    upgrade_database(engine)
    with Session(engine) as db:
        assert db.scalar(sa.select(sa.func.count()).select_from(ChatAutoReply)) == 8
        assert db.scalar(sa.select(sa.func.count()).select_from(BuyerMessage)) == 17
        for kind in ('support', 'cooperation', 'm_support', 'm_cooperation'):
            for event in AUTO_REPLY_TEXT:
                assert not create_auto_reply(db, 'buyer', kind, event)
        db.commit()
        assert db.scalar(sa.select(sa.func.count()).select_from(BuyerMessage)) == 17


def test_rollback_does_not_consume_auto_reply():
    engine = sa.create_engine('sqlite://')
    upgrade_database(engine)
    with Session(engine) as db:
        db.add(Buyer(id='buyer', email='rollback@example.com', name=''))
        db.commit()
        assert create_auto_reply(db, 'buyer', 'support', 'first_ack')
        db.flush()
        db.rollback()
        assert create_auto_reply(db, 'buyer', 'support', 'first_ack')
        db.commit()
        assert db.scalar(sa.select(sa.func.count()).select_from(ChatAutoReply)) == 1
        assert db.scalar(sa.select(sa.func.count()).select_from(BuyerMessage)) == 1


def run_concurrent_replies(engine):
    ready = Barrier(2, timeout=10)
    def send(index):
        with Session(engine) as db:
            ready.wait()
            # Both user messages must survive; only the automatic reply is deduplicated.
            db.add(BuyerMessage(id=f'concurrent-{index}', buyer='buyer', kind='support',
                               text=f'Question {index}', sent=float(index), staff=False))
            result = create_auto_reply(db, 'buyer', 'support', 'first_ack')
            db.commit()
            return result
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(send, range(2))) == [False, True]
    with Session(engine) as db:
        assert db.scalar(sa.select(sa.func.count()).select_from(ChatAutoReply).where(
            ChatAutoReply.buyer == 'buyer', ChatAutoReply.kind == 'support',
            ChatAutoReply.event == 'first_ack')) == 1
        assert db.scalar(sa.select(sa.func.count()).select_from(BuyerMessage).where(
            BuyerMessage.id.in_(['concurrent-0', 'concurrent-1']))) == 2


def test_concurrent_sqlite_replies(tmp_path):
    engine = sa.create_engine('sqlite:///' + str(tmp_path / 'parallel.db'))
    upgrade_database(engine)
    with Session(engine) as db:
        db.add(Buyer(id='buyer', email='parallel@example.com', name=''))
        db.commit()
    run_concurrent_replies(engine)


def test_account_deletion_removes_reply_markers(setup):
    client, codes, sessions = setup
    auth = login(client, codes, 'delete@example.com')
    assert client.get('/api/v1/account/messages?kind=support&with_greeting=true', headers=auth).status_code == 200
    assert client.delete('/api/v1/account', headers=auth).status_code == 200
    with sessions() as db:
        assert db.scalar(sa.select(sa.func.count()).select_from(ChatAutoReply)) == 0
