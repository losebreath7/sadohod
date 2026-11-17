"""Seller scenarios: nullable price, approved copies and atomic visibility."""
import pytest
from test_merchant_v080 import env, photo, make_published, approve
from test_merchant_operations import setup


def test_optional_price_survives_save_publish_and_buyer_serialization(env):
    c, auth, _, source, dest, _, _ = setup(env)
    pid = c.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
           files={'files': ('image.jpg', photo(), 'image/jpeg')})
    payload = {'request_id': 'nullable-price-save', 'title': '', 'category': 'Одежда',
               'listings': [{'pavilion_id': source, 'sale_modes': ['wholesale']},
                            {'pavilion_id': dest, 'price': 100, 'sale_modes': ['retail']}]}
    url = f'/api/v1/merchant/products/{pid}/save'
    r = c.put(url, headers=auth, json=payload)
    assert r.status_code == 200, r.text
    assert c.put(url, headers=auth, json=payload).status_code == 200
    assert any(l['price'] is None for l in r.json()['listings'])
    assert r.json()['status'] == 'approved'
    public = c.get(f'/api/v1/products/{pid}')
    assert public.status_code == 200, public.text
    assert public.json()['price'] == 100
    assert sorted(o['price'] is None for o in public.json()['offers']) == [False, True]


@pytest.mark.parametrize('price', [-1, 100000001, 1.5, '10', True])
def test_optional_price_still_rejects_invalid_values(env, price):
    c, auth, _, source, _, _, _ = setup(env)
    pid = c.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    assert c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
                  json={'pavilion_id': source, 'price': price, 'sale_modes': ['retail']}).status_code == 422


def test_visibility_batch_rolls_back_and_retries_then_resumes_immediately(env):
    c, auth, _, source, _, _, _ = setup(env)
    pid = make_published(c, auth, source)
    body = {'request_id': 'atomic-pause-1', 'product_ids': [pid, 'missing'], 'pavilion_id': source}
    url = '/api/v1/merchant/products/actions/'
    assert c.post(url+'pause', headers=auth, json=body).status_code == 404
    assert c.get('/api/v1/products/'+pid).status_code == 200
    body['product_ids'] = [pid]
    assert c.post(url+'pause', headers=auth, json=body).status_code == 200
    assert c.post(url+'pause', headers=auth, json=body).status_code == 200
    assert c.get('/api/v1/products/'+pid).status_code == 404
    body['request_id'] = 'atomic-resume-1'
    assert c.post(url+'resume', headers=auth, json=body).status_code == 200
    assert c.post(url+'resume', headers=auth, json=body).status_code == 200
    assert c.get('/api/v1/products/'+pid).status_code == 200
    row = c.get('/api/v1/merchant/products/'+pid, headers=auth).json()['listings'][0]
    assert row['status'] == 'approved'


def test_approved_copy_needs_no_product_moderation(env):
    c, auth, _, source, dest, _, _ = setup(env)
    pid = make_published(c, auth, source)
    edit = c.put('/api/v1/merchant/products/'+pid, headers=auth,
                 json={'title':'Изменён'})
    assert edit.status_code == 200
    assert c.get('/api/v1/products/'+pid).status_code == 200
    r = c.post('/api/v1/merchant/products/actions/copy', headers=auth, json={
        'request_id':'unapproved-copy-1', 'product_ids':[pid], 'source_pavilion_id':source,
        'destination_pavilion_ids':[dest]})
    assert r.status_code == 201, r.text
    copy_id = r.json()['copies'][0]['id']
    assert c.get('/api/v1/products/'+copy_id).status_code == 200
