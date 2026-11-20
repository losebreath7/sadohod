"""Notification tests: real moderation decisions and private, persistent reads."""
from io import BytesIO

from PIL import Image

from backend.tests.test_merchant_v080 import env, login, applicant, admin_client, approve


def test_shop_approval_and_rejection_emit_real_private_events(env):
    client, codes, sessions, _ = env
    alice = login(client, codes, 'alice-notify@example.com')
    bob = login(client, codes, 'bob-notify@example.com')
    assert client.get('/api/v1/merchant/notifications').status_code == 401

    aid = applicant(client, '129', alice)
    before = client.get('/api/v1/merchant/notifications', headers=alice).json()
    assert before['unread'] == 1
    assert before['items'][0]['event_type'] == 'application'
    assert before['items'][0]['target_id'] == aid
    assert before['items'][0]['title'] == 'Заявка на магазин отправлена'
    assert client.get('/api/v1/merchant/notifications', headers=bob).json()['items'] == []

    admin_client(client)
    approve(client, 'applications/' + aid + '/decision')
    inbox = client.get('/api/v1/merchant/notifications', headers=alice).json()
    assert inbox['unread'] == 2
    assert inbox['items'][0]['title'] == 'Магазин подтверждён'

    nid = inbox['items'][0]['id']
    assert client.put('/api/v1/merchant/notifications/' + nid + '/read',
        headers=bob).status_code == 404
    assert client.put('/api/v1/merchant/notifications/' + nid + '/read',
        headers=alice).status_code == 200
    assert client.put('/api/v1/merchant/notifications/' + nid + '/read',
        headers=alice).status_code == 200
    updated = client.get('/api/v1/merchant/notifications', headers=alice).json()
    assert updated['unread'] == 1
    assert updated['items'][0]['read'] is True

    # Failed duplicate moderation cannot generate a phantom notification.
    assert client.post('/api/v1/admin/merchant/applications/'+aid+'/decision',
        json={'decision':'approved'}).status_code == 409
    assert len(client.get('/api/v1/merchant/notifications', headers=alice).json()['items']) == 2


def test_pavilion_and_product_moderation_keep_reasons_and_isolate_owner(env):
    client, codes, _, _ = env
    seller = login(client, codes, 'seller-notify@example.com')
    other = login(client, codes, 'other-notify@example.com')
    admin_client(client)
    approve(client, 'applications/'+applicant(client, '21', seller)+'/decision')

    request = client.post('/api/v1/merchant/pavilions',
        headers=seller, json={'zone':'Зона З', 'code':'33'})
    assert request.status_code == 201, request.text
    rid = request.json()['id']
    result = client.post('/api/v1/admin/merchant/pavilions/'+rid+'/decision',
        json={'decision':'rejected','note':'Уточните сектор'})
    assert result.status_code == 200, result.text
    inbox = client.get('/api/v1/merchant/notifications', headers=seller).json()
    assert inbox['items'][0]['event_type'] == 'pavilion'
    assert inbox['items'][0]['note'] == 'Уточните сектор'

    # Products are published without review and must not generate
    # misleading moderation notifications for the seller.
    pavilions = client.get('/api/v1/merchant/pavilions', headers=seller).json()['items']
    pid = client.post('/api/v1/merchant/products', headers=seller,
        json={'title':'Чёрная куртка','category':'Одежда'}).json()['id']
    image = BytesIO()
    Image.new('RGB',(80,80),'black').save(image, format='JPEG')
    image_response = client.post(f'/api/v1/merchant/products/{pid}/images', headers=seller,
        files={'files':('jacket.jpg', image.getvalue(), 'image/jpeg')})
    assert image_response.status_code == 201, image_response.text
    assert client.post(f'/api/v1/merchant/products/{pid}/listings',
        headers=seller, json={'pavilion_id':pavilions[0]['id'], 'price':1600,
                              'sale_modes':['retail']}).status_code == 201
    assert client.post(f'/api/v1/merchant/products/{pid}/submit',
        headers=seller).status_code == 200
    assert client.get('/api/v1/products/' + pid).status_code == 200
    inbox = client.get('/api/v1/merchant/notifications', headers=seller).json()
    assert not any(x['event_type'] in ('product', 'listing') for x in inbox['items'])
    assert client.get('/api/v1/merchant/notifications', headers=other).json()['items']==[]


def _moderated_product(client, auth, pavilion, title, request_id):
    from test_merchant_v080 import photo
    pid = client.post('/api/v1/merchant/products', headers=auth,
                      json={'title': title}).json()['id']
    uploaded = client.post(f'/api/v1/merchant/products/{pid}/images',
                           headers=auth, files={'files': ('sample.jpg', photo(), 'image/jpeg')})
    assert uploaded.status_code == 201, uploaded.text
    saved = client.put(f'/api/v1/merchant/products/{pid}/save',
        headers=auth, json={'request_id': request_id, 'title': title, 'submit': True,
        'listings': [{'pavilion_id': pavilion, 'price': 700, 'sale_modes':['retail']}]})
    assert saved.status_code == 200, saved.text
    assert saved.json()['status'] == 'pending'
    assert client.get(f'/api/v1/products/{pid}').status_code == 404
    return pid


def test_product_rejection_emits_one_private_notice_with_reason(env, monkeypatch):
    from test_instant_publication import setup_seller
    from backend.app import product_screening
    from test_moderation_release_guard import REAL_ASSESS
    monkeypatch.setattr(product_screening, 'assess', REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    other = login(client, env[1], 'other-product-notify@example.com')
    pid = _moderated_product(client, auth, pavilion, 'Настоящий пистолет',
                             'notice-reject-01')
    before = [x for x in client.get('/api/v1/merchant/notifications', headers=auth)
              .json()['items'] if x['event_type'] == 'product']
    assert len(before) == 1
    assert before[0]['status'] == 'pending'
    assert before[0]['target_id'] == pid
    assert client.get('/api/v1/merchant/notifications', headers=other).json()['items'] == []

    denied = client.post(f'/api/v1/admin/merchant/products/{pid}/decision',
                         json={'decision': 'rejected', 'note': 'Запрещённый товар'})
    assert denied.status_code == 200, denied.text
    inbox = [x for x in client.get('/api/v1/merchant/notifications', headers=auth)
             .json()['items'] if x['event_type'] == 'product']
    assert len(inbox) == 2, inbox
    assert {x['status'] for x in inbox} == {'pending', 'rejected'}
    rejected = next(x for x in inbox if x['status'] == 'rejected')
    assert rejected['note'] == 'Запрещённый товар'
    assert rejected['target_id'] == pid
    assert client.put('/api/v1/merchant/notifications/' + rejected['id'] + '/read',
                      headers=auth).status_code == 200
    assert client.post(f'/api/v1/admin/merchant/products/{pid}/decision',
        json={'decision': 'rejected', 'note':'Повторно'}).status_code == 409
    after = [x for x in client.get('/api/v1/merchant/notifications', headers=auth)
             .json()['items'] if x['event_type'] == 'product']
    assert len(after) == 2
    assert next(x for x in after if x['id'] == rejected['id'])['read'] is True


def test_product_moderator_approval_emits_notice_but_no_listing_duplicates(env, monkeypatch):
    from test_instant_publication import setup_seller
    from backend.app import product_screening
    from test_moderation_release_guard import REAL_ASSESS
    monkeypatch.setattr(product_screening, 'assess', REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    pid = _moderated_product(client, auth, pavilion, 'Настоящий револьвер',
                             'notice-approve-01')
    decided = client.post(f'/api/v1/admin/merchant/products/{pid}/decision',
                          json={'decision': 'approved', 'category': 'Одежда'})
    assert decided.status_code == 200, decided.text
    assert client.get('/api/v1/products/' + pid).status_code == 200
    inbox = client.get('/api/v1/merchant/notifications', headers=auth).json()['items']
    product_events = [x for x in inbox if x['event_type'] == 'product' and x['target_id'] == pid]
    assert len(product_events) == 2, product_events
    assert {x['status'] for x in product_events} == {'pending', 'approved'}
    assert not any(x['event_type'] == 'listing' for x in inbox)
