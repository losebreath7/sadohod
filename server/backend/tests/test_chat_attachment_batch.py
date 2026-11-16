"""HTTP regression: histories select thumbnails once and never select raw files."""
import pytest
from sqlalchemy import event, select

from backend.tests.test_account import setup, login
from backend.app.account import Buyer
from backend.app.buyer_extras import BuyerMessage, BuyerChatAttachment
from backend.app.merchant_models import ShopApplication


@pytest.mark.parametrize('merchant', [False, True])
@pytest.mark.parametrize('kind', ['support', 'cooperation'])
@pytest.mark.parametrize('count', [1, 105])
def test_history_batches_metadata_without_file_bodies(setup, merchant, kind, count):
    client, codes, sessions = setup
    alice = login(client, codes, 'alice@example.com')
    bob = login(client, codes, 'bob@example.com')
    namespace = 'm_' + kind if merchant else kind
    raw = b'private full attachment contents'
    with sessions() as db:
        owner = db.scalar(select(Buyer.id).where(Buyer.email == 'alice@example.com'))
        other = db.scalar(select(Buyer.id).where(Buyer.email == 'bob@example.com'))
        for buyer_id in (owner, other):
            db.add(ShopApplication(id=buyer_id, buyer_id=buyer_id,
                shop_name='', zone='test', code=buyer_id))
        for i in range(count):
            db.add(BuyerMessage(id=f'm{i}', buyer=owner, kind=namespace,
                text='', sent=float(i), staff=bool(i % 2)))
            db.add(BuyerChatAttachment(id=f'a{i}', buyer=owner, message_id=f'm{i}',
                filename='photo.jpg', mime='image/jpeg', raw=raw, preview='dGh1bWI='))
        # Plain text and a malformed foreign-owner attachment must not acquire metadata.
        db.add(BuyerMessage(id='plain', buyer=owner, kind=namespace,
            text='plain text', sent=1000., staff=False))
        db.add(BuyerChatAttachment(id='foreign', buyer=other, message_id='plain',
            filename='private.txt', mime='text/plain', raw=b'foreign', preview=''))
        db.commit()
        engine = db.get_bind()

    statements = []
    def capture(conn, cursor, statement, parameters, context, executemany):
        if statement.lstrip().upper().startswith('SELECT') and 'buyer_chat_attachments_v083' in statement:
            statements.append((statement, parameters))

    path = '/api/v1/merchant/chat/messages' if merchant else '/api/v1/account/messages'
    event.listen(engine, 'before_cursor_execute', capture)
    try:
        response = client.get(path, params={'kind': kind}, headers=alice)
        assert response.status_code == 200, response.text
        items = response.json()['items']
        assert len(statements) == 1
        sql, parameters = statements[0]
        assert '.raw' not in sql and '*' not in sql
        assert 'buyer_chat_attachments_v083.preview' in sql
        assert owner in parameters
        assert len(items) == min(100, count + 1 + int(merchant))
        assert items[-1]['text'] == 'plain text'
        assert 'attachment' not in items[-1]
        photos = [m for m in items if 'attachment' in m]
        assert len(photos) == min(99, count)
        for message in photos:
            assert message['attachment'] == {
                'id': 'a' + message['id'][1:], 'filename': 'photo.jpg',
                'mime': 'image/jpeg', 'preview': 'dGh1bWI=',
            }
        if count > 100:
            assert 'm0' not in parameters  # Only the current page is fetched.
        other_history = client.get(path, params={'kind': kind}, headers=bob)
        assert not any('attachment' in m for m in other_history.json()['items'])
        assert client.get(path, params={'kind': kind}).status_code == 401
        # Opening a file still delivers the exact bytes only to its owner.
        download = '/api/v1/account/messages/attachment/a0'
        assert client.get(download, headers=bob).status_code == 404
        assert client.get(download).status_code == 401
        statements.clear()
        assert client.get(download, headers=alice).content == raw
        assert any('.raw' in sql for sql, _ in statements)
    finally:
        event.remove(engine, 'before_cursor_execute', capture)


def test_empty_history_does_not_query_attachments(setup):
    client, codes, sessions = setup
    auth = login(client, codes, 'empty@example.com')
    with sessions() as db:
        engine = db.get_bind()
    statements = []
    def capture(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)
    event.listen(engine, 'before_cursor_execute', capture)
    try:
        response = client.get('/api/v1/account/messages?kind=support', headers=auth)
        assert response.json() == {'items': []}
        assert not any('buyer_chat_attachments_v083' in sql for sql in statements)
    finally:
        event.remove(engine, 'before_cursor_execute', capture)
