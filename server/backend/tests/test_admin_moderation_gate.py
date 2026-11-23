"""Regression tests for administrative paths that could bypass seller screening.

The fixtures intentionally mock the ML decision; they test the publication
gate, not OpenCLIP's detection quality on real photographs.
"""
from backend.app import admin, product_screening
from backend.tests.test_api import client  # fixture required by imported editor
from test_admin import editor, draft, upload
from test_instant_publication import setup_seller
from test_merchant_v080 import env, photo


def _fake_clip(monkeypatch):
    monkeypatch.setattr(admin, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(admin, 'embed_image',
                        lambda data: [1.0] + [0.0] * (admin.DIM - 1))


def test_admin_cannot_publish_unsafe_photo_with_indexed_ml_vector(editor, monkeypatch):
    c = editor
    _fake_clip(monkeypatch)
    p, _ = draft(c)
    pid = p['id']
    assert upload(c, pid).status_code == 201
    monkeypatch.setattr(product_screening, 'assess',
                        lambda db, product: 'Автопроверка: подозрительное фото')
    blocked = c.put(f'/api/v1/admin/products/{pid}/visibility',
                    json={'active': True})
    assert blocked.status_code == 409, blocked.text
    assert 'проверки модератора' in blocked.json()['detail']
    assert c.get('/api/v1/products/' + pid).status_code == 404
    monkeypatch.setattr(product_screening, 'assess', lambda db, product: None)
    cleared = c.put(f'/api/v1/admin/products/{pid}/visibility',
                    json={'active': True})
    assert cleared.status_code == 200, cleared.text
    assert c.get('/api/v1/products/' + pid).status_code == 200


def test_admin_risky_text_edit_unpublishes_visible_legacy_product(editor, monkeypatch):
    c = editor
    p, payload = draft(c)
    pid = p['id']
    assert upload(c, pid).status_code == 201
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',
                 json={'active': True}).status_code == 200
    _fake_clip(monkeypatch)
    monkeypatch.setattr(product_screening, 'assess',
                        lambda db, product: ('Автопроверка: оружие' if
                                             'револьвер' in product.title else None))
    changed = c.put(f'/api/v1/admin/products/{pid}',
                    json={**payload, 'title': 'Настоящий револьвер'})
    assert changed.status_code == 200, changed.text
    assert c.get('/api/v1/products/' + pid).status_code == 404
    blocked = c.put(f'/api/v1/admin/products/{pid}/visibility',
                    json={'active': True})
    assert blocked.status_code == 409


def test_admin_new_photo_cannot_remain_public_until_rechecked(editor, monkeypatch):
    c = editor
    p, _ = draft(c)
    pid = p['id']
    assert upload(c, pid).status_code == 201
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',
                 json={'active': True}).status_code == 200
    _fake_clip(monkeypatch)
    monkeypatch.setattr(product_screening, 'assess',
                        lambda db, product: 'Автопроверка: опасное фото')
    response = upload(c, pid)
    assert response.status_code == 201, response.text
    assert len(response.json()['images']) == 2
    assert c.get('/api/v1/products/' + pid).status_code == 404


def test_admin_visibility_cannot_publish_pending_merchant_item(env):
    c, auth, pavilion = setup_seller(env)
    pid = c.post('/api/v1/merchant/products', headers=auth,
                 json={'title': 'Настоящий пистолет'}).json()['id']
    assert c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                  files={'files': ('photo.jpg', photo(), 'image/jpeg')}).status_code == 201
    listing = c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
                     json={'pavilion_id': pavilion, 'price': 100,
                           'sale_modes': ['retail']})
    assert listing.status_code == 201, listing.text
    assert c.post(f'/api/v1/merchant/products/{pid}/submit',
                  headers=auth).json()['status'] == 'pending'
    blocked = c.put(f'/api/v1/admin/products/{pid}/visibility',
                    json={'active': True})
    assert blocked.status_code == 409
    assert c.get('/api/v1/products/' + pid).status_code == 404
