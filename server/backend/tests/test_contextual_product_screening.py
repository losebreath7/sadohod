"""Regression coverage for contextual seller screening (classic backend, text path).

Image triage in clip mode requires indexed OpenCLIP photo vectors and a
calibrated labeled photo set; it must not be called a production classifier
based only on these deterministic API tests.
"""
from backend.app import product_screening as s
from test_instant_publication import setup_seller

REAL_ASSESS = s.assess
from test_merchant_v080 import env, photo


def _new(client, auth, pavilion, title, key):
    item = client.post('/api/v1/merchant/products', headers=auth,
                       json={'title': title}).json()
    pid = item['id']
    response = client.post(f'/api/v1/merchant/products/{pid}/images',
        headers=auth, files={'files': ('test.jpg', photo(), 'image/jpeg')})
    assert response.status_code == 201, response.text
    data = {'request_id': key, 'title': title, 'submit': True,
            'listings': [{'pavilion_id': pavilion, 'price': 350,
                          'sale_modes': ['retail']}]}
    return pid, data


def test_actual_weapon_text_goes_to_staff_without_public_offer(env):
    client, auth, pavilion = setup_seller(env)
    pid, body = _new(client, auth, pavilion, 'Настоящий пистолет', 'screen-gun-save-1')
    saved = client.put(f'/api/v1/merchant/products/{pid}/save',
                       headers=auth, json=body)
    assert saved.status_code == 200, saved.text
    assert saved.json()['status'] == 'pending'
    assert saved.json()['listings'][0]['published'] is False
    assert client.get(f'/api/v1/products/{pid}').status_code == 404
    queued = client.get('/api/v1/admin/merchant/queue').json()
    assert pid in {p['id'] for p in queued['products']}
    assert any(p['id'] == pid and p['note'].startswith('Автопроверка')
               for p in queued['products'])


def test_shirt_with_weapon_print_is_not_a_physical_weapon(env, monkeypatch):
    monkeypatch.setattr(s, 'assess', REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    pid, body = _new(client, auth, pavilion, 'Футболка с принтом пистолета', 'screen-print-save-1')
    saved = client.put(f'/api/v1/merchant/products/{pid}/save',
                       headers=auth, json=body)
    assert saved.status_code == 200, saved.text
    assert saved.json()['status'] == 'pending'
    assert saved.json()['listings'][0]['published'] is False
    assert 'classic' in saved.json()['note']
    assert client.get(f'/api/v1/products/{pid}').status_code == 404


def test_editing_published_item_into_weapon_removes_live_offer(env):
    client, auth, pavilion = setup_seller(env)
    pid, body = _new(client, auth, pavilion, 'Сувенир', 'screen-edit-save-1')
    assert client.put(f'/api/v1/merchant/products/{pid}/save',
                      headers=auth, json=body).json()['status'] == 'approved'
    changed = client.put(f'/api/v1/merchant/products/{pid}', headers=auth,
                         json={'title': 'Настоящий револьвер'})
    assert changed.status_code == 200, changed.text
    assert changed.json()['status'] == 'pending'
    assert all(not row['published'] for row in changed.json()['listings'])
    assert client.get(f'/api/v1/products/{pid}').status_code == 404
    assert client.post('/api/v1/merchant/products/actions/resume', headers=auth,
        json={'request_id': 'screen-edit-resume-1', 'product_ids': [pid]}).status_code == 409
