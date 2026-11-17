"""Approved sellers publish products automatically; pavilion claims stay moderated."""
from test_merchant_v080 import env, login, applicant, admin_client, approve, photo


def setup_seller(env):
    client, codes, _, _ = env
    auth = login(client, codes, 'instant-publication@test.com')
    admin_client(client)
    application = applicant(client, 'instant-1', auth)
    approve(client, f'applications/{application}/decision')
    pavilion = client.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    return client, auth, pavilion


def test_first_and_later_pavilions_require_moderation(env):
    client, auth, first = setup_seller(env)
    response = client.post('/api/v1/merchant/pavilions', headers=auth,
                           json={'zone': 'Линия B', 'code': 'instant-2'})
    assert response.status_code == 201, response.text
    request_id = response.json()['id']
    assert response.json()['status'] == 'pending'
    before = client.get('/api/v1/merchant/pavilions', headers=auth).json()
    assert len(before['items']) == 1
    assert any(r['id'] == request_id and r['status'] == 'pending' for r in before['requests'])
    approve(client, f'pavilions/{request_id}/decision')
    after = client.get('/api/v1/merchant/pavilions', headers=auth).json()
    assert len(after['items']) == 2


def test_first_save_and_restart_publication_without_product_moderation(env):
    client, auth, pavilion = setup_seller(env)
    create = client.post('/api/v1/merchant/products', headers=auth, json={
        'request_id': 'instant-create-1', 'title': 'Неизвестный предмет'})
    assert create.status_code == 201, create.text
    pid = create.json()['id']
    assert client.get('/api/v1/products/' + pid).status_code == 404
    upload = client.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                         files={'files': ('photo.jpg', photo(), 'image/jpeg')})
    assert upload.status_code == 201, upload.text
    payload = {'request_id': 'instant-save-1', 'title': 'Неизвестный предмет',
               'listings': [{'pavilion_id': pavilion, 'price': 900,
                             'sale_modes': ['retail']}], 'submit': True}
    save = client.put(f'/api/v1/merchant/products/{pid}/save', headers=auth, json=payload)
    assert save.status_code == 200, save.text
    assert save.json()['status'] == 'approved'
    assert save.json()['listings'][0]['published'] is True
    assert client.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
                      json=payload).status_code == 200
    assert client.get('/api/v1/products/' + pid).status_code == 200
    queue = client.get('/api/v1/admin/merchant/queue').json()
    assert not queue['products'] and not queue['listings']
    visibility = '/api/v1/merchant/products/actions/'
    paused = client.post(visibility + 'pause', headers=auth, json={
        'request_id': 'instant-pause-1', 'product_ids': [pid]})
    assert paused.status_code == 200, paused.text
    assert client.get('/api/v1/products/' + pid).status_code == 404
    resumed = client.post(visibility + 'resume', headers=auth, json={
        'request_id': 'instant-resume-1', 'product_ids': [pid]})
    assert resumed.status_code == 200, resumed.text
    assert resumed.json()['status'] == 'approved'
    assert client.get('/api/v1/products/' + pid).status_code == 200
    updated = client.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
                         json={**payload, 'request_id': 'instant-save-2',
                               'title': 'Обновлённое название'})
    assert updated.status_code == 200, updated.text
    assert updated.json()['status'] == 'approved'
    assert client.get('/api/v1/products/' + pid).json()['title'] == 'Обновлённое название'


def test_unapproved_pavilion_cannot_receive_product(env):
    client, auth, first = setup_seller(env)
    pending = client.post('/api/v1/merchant/pavilions', headers=auth, json={
        'zone': 'Линия B', 'code': 'instant-3'})
    assert pending.status_code == 201
    pid = client.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    client.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                files={'files': ('photo.jpg', photo(), 'image/jpeg')})
    body = {'request_id': 'no-unapproved-1', 'title': 'Товар', 'submit': True,
            'listings': [{'pavilion_id': pending.json()['id'], 'price': 100,
                          'sale_modes': ['retail']}]}
    response = client.put(f'/api/v1/merchant/products/{pid}/save', headers=auth, json=body)
    assert response.status_code == 403
    assert client.get('/api/v1/products/' + pid).status_code == 404
