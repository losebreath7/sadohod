"""Seller chat uses buyer's attachment store, distinct namespaces and owner checks."""
import base64

import pytest
from sqlalchemy import select

from backend.app.account import Buyer
from backend.app.buyer_extras import BuyerMessage, BuyerChatAttachment
from backend.app.merchant_models import ShopApplication
from backend.app.telegram_bridge import TelegramOutbox
from backend.tests.test_account import setup, login


@pytest.mark.parametrize('kind', ['support', 'cooperation'])
def test_seller_attachment_is_visible_and_forwarded_only_in_seller_chat(setup, kind):
    client, codes, sessions = setup
    owner = login(client, codes, f'seller-{kind}@example.com')
    stranger = login(client, codes, f'other-{kind}@example.com')
    body = {'kind': kind, 'filename': 'note.txt',
            'data': base64.b64encode('Тест файла'.encode('utf-8')).decode(),
            'text': ''}
    assert client.post('/api/v1/merchant/chat/messages/attachment', headers=owner, json=body).status_code == 403
    assert client.post('/api/v1/merchant/chat/messages/attachment', json=body).status_code == 401
    with sessions() as db:
        buyer = db.scalar(select(Buyer).where(Buyer.email == f'seller-{kind}@example.com'))
        db.add(ShopApplication(id='shop-'+kind, buyer_id=buyer.id,
            shop_name='', zone='test', code=kind))
        db.commit()
    posted = client.post('/api/v1/merchant/chat/messages/attachment', headers=owner, json=body)
    assert posted.status_code == 201, posted.text
    mid = posted.json()['id']
    history = client.get('/api/v1/merchant/chat/messages', params={'kind': kind}, headers=owner)
    assert history.status_code == 200
    attached = [r for r in history.json()['items'] if r['id'] == mid]
    assert len(attached) == 1 and attached[0]['attachment']['filename'] == 'note.txt'
    assert attached[0]['staff'] is False
    assert attached[0]['delivered'] is False
    namespace = 'm_'+kind
    # Delivery flags are scoped to the seller, chat kind and message ID.
    with sessions() as db:
        row = db.scalar(select(TelegramOutbox).where(TelegramOutbox.message_id == mid))
        assert row is not None and row.kind == namespace
        row.delivered = True
        db.commit()
    history = client.get('/api/v1/merchant/chat/messages', params={'kind': kind}, headers=owner)
    updated = [m for m in history.json()['items'] if m['id'] == mid]
    assert len(updated) == 1 and updated[0]['delivered'] is True
    assert all('delivered' not in m for m in history.json()['items'] if m['staff'])
    with sessions() as db:
        db_message = db.get(BuyerMessage, mid)
        assert db_message.kind == namespace
        attachment = db.scalar(select(BuyerChatAttachment).where(BuyerChatAttachment.message_id == mid))
        assert attachment is not None and attachment.raw == 'Тест файла'.encode('utf-8')
        attachment_id = attachment.id
    assert client.get('/api/v1/account/messages', params={'kind': kind}, headers=owner).json()['items'] == []
    assert client.get('/api/v1/merchant/chat/messages', params={'kind': kind}, headers=stranger).status_code == 403
    assert client.get('/api/v1/account/messages/attachment/'+attachment_id, headers=stranger).status_code == 404
    assert client.get('/api/v1/account/messages/attachment/'+attachment_id, headers=owner).content == 'Тест файла'.encode('utf-8')
    # Same welcome and first acknowledgement as buyer: one of each, not per message.
    again = client.post('/api/v1/merchant/chat/messages/attachment', headers=owner, json=body)
    assert again.status_code == 201, again.text
    rows = client.get('/api/v1/merchant/chat/messages', params={'kind':kind}, headers=owner).json()['items']
    assert sum(m['text'] == 'запрос передан менеджеру, ожидаем ответа, помним о бренности бытия' for m in rows) == 1
    assert [m['delivered'] for m in rows if not m['staff']] == [True, False]


def test_seller_attachment_rejects_invalid_file_and_missing_auth(setup):
    client, codes, sessions = setup
    owner = login(client, codes, 'upload@example.com')
    with sessions() as db:
        buyer = db.scalar(select(Buyer).where(Buyer.email == 'upload@example.com'))
        db.add(ShopApplication(id='upload_shop', buyer_id=buyer.id, shop_name='', zone='test', code='1'))
        db.commit()
    req = {'kind':'support', 'filename':'invalid.exe', 'data':base64.b64encode(b'payload').decode()}
    assert client.post('/api/v1/merchant/chat/messages/attachment', headers=owner, json=req).status_code == 422
    assert client.get('/api/v1/merchant/chat/messages', headers=owner, params={'kind':'support'}).status_code == 200
