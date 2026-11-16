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
    assert before['items'][0]['title'] == 'На проверке'
    assert client.get('/api/v1/merchant/notifications', headers=bob).json()['items'] == []

    admin_client(client)
    approve(client, 'applications/' + aid + '/decision')
    inbox = client.get('/api/v1/merchant/notifications', headers=alice).json()
    assert inbox['unread'] == 2
    assert inbox['items'][0]['title'] == 'Проверка пройдена'

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

    # Product awaiting moderation stays private until a decision.
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
    decision = client.post(f'/api/v1/admin/merchant/products/{pid}/decision',
        json={'decision':'rejected', 'note':'Замените основную фотографию'})
    assert decision.status_code == 200, decision.text
    inbox = client.get('/api/v1/merchant/notifications', headers=seller).json()
    rejected = [n for n in inbox['items']
                if n['event_type'] == 'product' and n['target_id'] == pid
                and n['title'] == 'Не прошло модерацию']
    assert len(rejected) == 1
    assert rejected[0]['note'] == 'Замените основную фотографию'
    assert any(x['event_type']=='product' and x['title']=='На проверке'
               for x in inbox['items'])
    assert client.get('/api/v1/merchant/notifications', headers=other).json()['items']==[]
