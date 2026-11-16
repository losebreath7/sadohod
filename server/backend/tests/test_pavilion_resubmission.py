from sqlalchemy import select, func
from backend.app.merchant_models import ShopApplication, PavilionRequest
from backend.tests.test_merchant_v080 import env, login, admin_client, applicant, approve


def test_first_application_reopens_retries_and_approves(env):
    c, codes, factory, _ = env
    auth = login(c, codes, 'onboarding@example.com')
    body = {'shop_name':'Продавец', 'contact':'@seller', 'zone':'Линия Б', 'code':'Б-2В-82'}
    result = c.post('/api/v1/merchant/applications', headers=auth, json=body)
    assert result.status_code == 201
    aid = result.json()['id']
    assert c.post('/api/v1/merchant/applications', headers=auth, json=body).json()['id'] == aid
    status = c.get('/api/v1/merchant/me', headers=auth).json()
    assert status['shop'] is None
    assert [(a['id'], a['status']) for a in status['applications']] == [(aid, 'pending')]
    assert c.post('/api/v1/merchant/products', headers=auth, json={'title':''}).status_code == 403
    assert c.put('/api/v1/merchant/applications/'+aid, headers=auth, json={**body,'code':'83'}).status_code == 409
    admin_client(c)
    response = c.post(f'/api/v1/admin/merchant/applications/{aid}/decision',
        json={'decision':'rejected','note':'Проверьте номер павильона'})
    assert response.status_code == 200
    status = c.get('/api/v1/merchant/me', headers=auth).json()['applications'][0]
    assert status['note'] == 'Проверьте номер павильона'
    body['code'] = 'Б-2В-83'
    for _ in range(2):
        response = c.put('/api/v1/merchant/applications/'+aid, headers=auth, json=body)
        assert response.status_code == 200, response.text
        assert response.json()['id'] == aid and response.json()['status'] == 'pending'
        assert response.json()['note'] == ''
    with factory() as db:
        assert db.scalar(select(func.count()).select_from(ShopApplication)) == 1
    approve(c, f'applications/{aid}/decision')
    me = c.get('/api/v1/merchant/me', headers=auth).json()
    assert me['shop'] is not None and me['applications'][0]['status'] == 'approved'
    confirmed = c.get('/api/v1/merchant/pavilions', headers=auth).json()
    assert len(confirmed['items']) == 1 and confirmed['requests'] == []
    assert confirmed['items'][0]['code'] == body['code']
    assert c.put('/api/v1/merchant/applications/'+aid, headers=auth, json=body).status_code == 409


def test_additional_pavilion_resubmits_same_record_and_blocks_unapproved_listing(env):
    c, codes, factory, _ = env
    auth = login(c, codes, 'multiple@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c,"main",auth)}/decision')
    body = {'zone':'Линия Б','code':'82'}
    rid = c.post('/api/v1/merchant/pavilions', headers=auth, json=body).json()['id']
    assert c.post('/api/v1/merchant/pavilions', headers=auth, json=body).json()['id'] == rid
    data = c.get('/api/v1/merchant/pavilions', headers=auth).json()
    assert len(data['items']) == 1 and len(data['requests']) == 1
    pid = c.post('/api/v1/merchant/products', headers=auth, json={'title':'Тест'}).json()['id']
    result = c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
        json={'pavilion_id':rid,'price':10,'sale_modes':['retail']})
    assert result.status_code == 403
    approve(c, f'pavilions/{rid}/decision', decision='rejected')
    body['code'] = '83'
    for _ in range(2):
        result = c.put(f'/api/v1/merchant/pavilions/requests/{rid}', headers=auth, json=body)
        assert result.status_code == 200, result.text
        assert result.json()['id'] == rid and result.json()['status'] == 'pending'
    with factory() as db:
        assert db.scalar(select(func.count()).select_from(PavilionRequest)) == 1
    approve(c, f'pavilions/{rid}/decision')
    data = c.get('/api/v1/merchant/pavilions', headers=auth).json()
    assert len(data['items']) == 2 and data['requests'] == []
    confirmed_id = next(p['id'] for p in data['items'] if p['code'] == '83')
    assert c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
        json={'pavilion_id':confirmed_id,'price':10,'sale_modes':['retail']}).status_code == 201


def test_resubmission_is_owner_only_and_checks_other_pending_addresses(env):
    c, codes, _, _ = env
    a = login(c, codes, 'owner@example.com')
    b = login(c, codes, 'other@example.com')
    admin_client(c)
    aid = applicant(c,'first',a)
    approve(c, f'applications/{aid}/decision', decision='rejected')
    body = {'shop_name':'Продавец','zone':'Линия А','code':'first'}
    assert c.put('/api/v1/merchant/applications/'+aid, headers=b, json=body).status_code == 404
    assert c.put('/api/v1/merchant/applications/'+aid, json=body).status_code == 401
    pending = applicant(c, 'second', a)
    assert c.put('/api/v1/merchant/applications/'+aid, headers=a, json=body).status_code == 409
    approve(c, f'applications/{pending}/decision')
    approve(c, f'applications/{applicant(c,"other",b)}/decision')
    req = c.post('/api/v1/merchant/pavilions', headers=a, json={'zone':'Б','code':'10'}).json()['id']
    approve(c, f'pavilions/{req}/decision', decision='rejected')
    body = {'zone':'Б','code':'11'}
    assert c.put(f'/api/v1/merchant/pavilions/requests/{req}', headers=b, json=body).status_code == 404
    c.post('/api/v1/merchant/pavilions', headers=a, json=body)
    assert c.put(f'/api/v1/merchant/pavilions/requests/{req}', headers=a, json=body).status_code == 409
