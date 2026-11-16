"""v0.8.1 tests: new tables are additive; no old buyer data is dropped."""
import base64
import io
from PIL import Image
from sqlalchemy import select

from backend.tests.test_account import setup, login
from backend.app import buyer_extras as extra
from backend.app import account as auth


def test_profile_media_auth_validation_isolation_and_delete(setup):
    client, codes, sessions = setup
    first = login(client, codes, 'first@example.com')
    second = login(client, codes, 'second@example.com')
    img = Image.new('RGB', (100, 100), (220, 220, 220))
    file = io.BytesIO()
    img.save(file, format='JPEG')
    payload = {'kind': 'avatar', 'data': base64.b64encode(file.getvalue()).decode()}
    assert client.get('/api/v1/account/media').status_code == 401
    assert client.post('/api/v1/account/media', headers=first, json=payload).status_code == 200
    result = client.get('/api/v1/account/media', headers=first).json()
    assert result['cover'] == ''
    assert base64.b64decode(result['avatar'])[:3] == b'\xff\xd8\xff'
    assert client.get('/api/v1/account/media', headers=second).json()['avatar'] == ''
    assert client.post('/api/v1/account/media', headers=first,
        json={'kind': 'avatar', 'data': 'wrong~~'}).status_code == 422
    assert client.delete('/api/v1/account', headers=first).status_code == 200
    with sessions() as db:
        assert db.scalar(select(extra.BuyerMedia)) is None


def test_email_change_requires_code_preserves_favorites_and_sessions(setup, monkeypatch):
    client, codes, sessions = setup
    monkeypatch.setattr(extra, 'send_code', lambda mail, code: codes.update({mail: code}))
    first = login(client, codes, 'first@example.com')
    second = login(client, codes, 'first@example.com')
    client.post('/api/v1/account/favorite', headers=first,
                json={'kind': 'product', 'id': 'p01', 'saved': True})
    mail = 'new@example.com'
    assert client.post('/api/v1/account/email/request', headers=first, json={'email': mail}).status_code == 200
    assert client.post('/api/v1/account/email/confirm', headers=first,
        json={'email': mail, 'code': 'not-code'}).status_code == 422
    wrong = '000000' if codes[mail] != '000000' else '000001'
    assert client.post('/api/v1/account/email/confirm', headers=first,
        json={'email': mail, 'code': wrong}).status_code == 400
    r = client.post('/api/v1/account/email/confirm', headers=first,
        json={'email': mail, 'code': codes[mail]})
    assert r.status_code == 200, r.text
    assert client.get('/api/v1/account', headers=first).json()['email'] == mail
    assert client.get('/api/v1/account', headers=second).json()['products'] == ['p01']
    assert client.post('/api/v1/account/email/confirm', headers=first,
        json={'email': mail, 'code': codes[mail]}).status_code == 400


def test_message_threads_are_private_and_reject_unauthed(setup):
    client, codes, _ = setup
    first = login(client, codes, 'first@example.com')
    second = login(client, codes, 'second@example.com')
    assert client.post('/api/v1/account/messages', json={'kind': 'support', 'text': 'привет'}).status_code == 401
    assert client.post('/api/v1/account/messages', headers=first,
        json={'kind': 'support', 'text': 'вопрос про товар'}).status_code == 200
    assert client.post('/api/v1/account/messages', headers=first,
        json={'kind': 'cooperation', 'text': 'помощь продавцу'}).status_code == 200
    r = client.get('/api/v1/account/messages?kind=support', headers=first)
    assert r.status_code == 200 and len(r.json()['items']) == 1
    assert client.get('/api/v1/account/messages?kind=cooperation', headers=first).json()['items'][0]['text'] == 'помощь продавцу'
    assert client.get('/api/v1/account/messages?kind=support', headers=second).json()['items'] == []
    assert client.delete('/api/v1/account', headers=first).status_code == 200


def test_occupied_address_request_and_confirm(setup, monkeypatch):
    client, codes, _ = setup
    monkeypatch.setattr(extra, 'send_code', lambda mail, code: codes.update({mail: code}))
    owner = login(client, codes, 'owner@example.com')
    requester = login(client, codes, 'requester@example.com')
    dest = 'owner@example.com'
    response = client.post('/api/v1/account/email/request', headers=requester, json={'email': dest})
    assert response.json() == {'sent': True, 'expires_in': 600}
    body = {'email': dest, 'code': codes[dest]}
    for _ in range(2):
        assert client.post('/api/v1/account/email/confirm', headers=requester, json=body).status_code == 400
    assert client.get('/api/v1/account', headers=owner).json()['email'] == dest
    assert client.get('/api/v1/account', headers=requester).json()['email'] == 'requester@example.com'
