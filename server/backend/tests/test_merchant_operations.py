from pathlib import Path
import pytest
from sqlalchemy import select, text
from backend.app import merchant_operations as ops, category_inference as ci
from backend.app.models import Product, ImageMLEmbedding
from backend.app.merchant_models import MerchantProduct, MerchantListing
from backend.app.ml_clip import MODEL_ID, DIM
from test_merchant_v080 import env, login, applicant, approve, admin_client, photo, make_published


def setup(env):
    c, codes, factory, media = env
    auth = login(c, codes, 'operations@test.com')
    other = login(c, codes, 'other@test.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "ops1", auth)}/decision')
    approve(c, f'applications/{applicant(c, "ops2", other)}/decision')
    source = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    req = c.post('/api/v1/merchant/pavilions', headers=auth, json={'zone': 'Линия Б', 'code': 'ops3'}).json()['id']
    approve(c, f'pavilions/{req}/decision')
    destination = next(p['id'] for p in c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'] if p['id'] != source)
    with factory() as db:
        db.execute(text('PRAGMA foreign_keys=ON'))
    return c, auth, other, source, destination, factory, media


def test_copy_retry_independent_images_and_moderation(env):
    c, auth, _, source, dest, factory, media = setup(env)
    pid = make_published(c, auth, source)
    payload = {'request_id': 'copy-request-1', 'product_ids': [pid], 'source_pavilion_id': source,
               'destination_pavilion_ids': [dest]}
    r = c.post('/api/v1/merchant/products/actions/copy', headers=auth, json=payload)
    assert r.status_code == 201, r.text
    copied = r.json()['copies'][0]['id']
    assert copied != pid
    again = c.post('/api/v1/merchant/products/actions/copy', headers=auth, json=payload)
    assert again.json() == r.json()
    assert c.get('/api/v1/products/' + copied).status_code == 404
    data = c.get('/api/v1/merchant/products/' + copied, headers=auth).json()
    assert data['status'] == 'draft'
    assert data['listings'][0]['price'] == 2500
    assert data['listings'][0]['sale_modes'] == ['wholesale', 'retail']
    original = c.get('/api/v1/merchant/products/' + pid, headers=auth).json()
    assert data['images'] != original['images']
    original_file = media / original['images'][0].removeprefix('/media/products/')
    copy_file = media / data['images'][0].removeprefix('/media/products/')
    assert copy_file.read_bytes() == original_file.read_bytes()
    iid = data['image_items'][0]['id']
    assert c.delete(f'/api/v1/merchant/products/{copied}/images/{iid}', headers=auth).status_code == 200
    assert original_file.exists() and not copy_file.exists()
    assert c.get('/api/v1/products/' + pid).status_code == 200
    payload['destination_pavilion_ids'] = [source]
    assert c.post('/api/v1/merchant/products/actions/copy', headers=auth, json=payload).status_code == 409


def test_copy_rolls_back_files_and_rows(env, monkeypatch):
    c, auth, _, source, dest, factory, media = setup(env)
    pid = make_published(c, auth, source)
    before_files = set(media.rglob('*.jpg'))
    with factory() as db:
        before = db.query(Product).count()
    original = ops.clone_image
    def failing(*args):
        original(*args)
        raise RuntimeError('Simulated interrupted copy')
    monkeypatch.setattr(ops, 'clone_image', failing)
    with pytest.raises(RuntimeError, match='Simulated'):
        c.post('/api/v1/merchant/products/actions/copy', headers=auth, json={
            'request_id': 'failed-copy-1', 'product_ids': [pid], 'source_pavilion_id': source,
            'destination_pavilion_ids': [dest]})
    assert set(media.rglob('*.jpg')) == before_files
    with factory() as db:
        assert db.query(Product).count() == before


def test_move_is_atomic_and_requires_moderation(env):
    c, auth, _, source, dest, factory, _ = setup(env)
    pid = make_published(c, auth, source)
    body = {'request_id': 'move-request-1', 'product_ids': [pid, 'missing'],
            'source_pavilion_id': source, 'destination_pavilion_id': dest}
    assert c.post('/api/v1/merchant/products/actions/move', headers=auth, json=body).status_code == 404
    assert c.get('/api/v1/products/' + pid).status_code == 200
    body['product_ids'] = [pid]
    r = c.post('/api/v1/merchant/products/actions/move', headers=auth, json=body)
    assert r.status_code == 200, r.text
    assert c.post('/api/v1/merchant/products/actions/move', headers=auth, json=body).json() == r.json()
    data = c.get('/api/v1/merchant/products/' + pid, headers=auth).json()
    row = data['listings'][0]
    assert row['pavilion_id'] == dest and row['status'] == 'pending'
    assert c.get('/api/v1/products/' + pid).status_code == 404
    approve(c, 'listings/' + row['id'] + '/decision')
    assert c.get('/api/v1/products/' + pid).status_code == 200


def test_tenant_isolation_and_pending_block(env):
    c, auth, other, source, dest, factory, _ = setup(env)
    pid = make_published(c, auth, source)
    iid = c.get('/api/v1/merchant/products/' + pid, headers=auth).json()['image_items'][0]['id']
    assert c.delete('/api/v1/merchant/products/' + pid, headers=other).status_code == 404
    assert c.delete(f'/api/v1/merchant/products/{pid}/images/{iid}', headers=other).status_code == 404
    assert c.post('/api/v1/merchant/products/actions/copy', headers=other, json={
        'request_id': 'unauthorized-copy', 'product_ids': [pid], 'source_pavilion_id': source,
        'destination_pavilion_ids': [dest]}).status_code == 403
    assert c.put('/api/v1/merchant/products/' + pid, headers=auth,
                 json={'title': 'Изменено', 'category': 'Одежда'}).status_code == 200
    assert c.post('/api/v1/merchant/products/' + pid + '/submit', headers=auth).status_code == 200
    assert c.delete('/api/v1/merchant/products/' + pid, headers=auth).status_code == 409
    assert c.delete(f'/api/v1/merchant/products/{pid}/images/{iid}', headers=auth).status_code == 409


def test_archive_bulk_all_or_nothing_and_idempotent(env):
    c, auth, _, source, dest, factory, _ = setup(env)
    pid = make_published(c, auth, source)
    url = '/api/v1/merchant/products/actions/delete'
    body = {'request_id': 'delete-request-1', 'product_ids': [pid, 'missing']}
    assert c.post(url, headers=auth, json=body).status_code == 404
    assert c.get('/api/v1/products/' + pid).status_code == 200
    body['product_ids'] = [pid]
    assert c.post(url, headers=auth, json=body).status_code == 200
    assert c.post(url, headers=auth, json=body).status_code == 200
    assert c.delete('/api/v1/merchant/products/' + pid, headers=auth).status_code == 200
    assert c.get('/api/v1/products/' + pid).status_code == 404
    assert c.get('/api/v1/merchant/products/' + pid, headers=auth).status_code == 404
    assert c.get('/api/v1/merchant/products', headers=auth).json()['items'] == []
    with factory() as db:
        assert db.get(Product, pid) is not None
        assert db.get(MerchantProduct, pid).status == 'deleted'
        assert not db.get(Product, pid).offers


def test_delete_published_photo_hides_until_resubmitted(env):
    c, auth, _, source, _, _, _ = setup(env)
    pid = make_published(c, auth, source)
    data = c.get('/api/v1/merchant/products/' + pid, headers=auth).json()
    r = c.delete(f"/api/v1/merchant/products/{pid}/images/{data['image_items'][0]['id']}", headers=auth)
    assert r.status_code == 200, r.text
    assert r.json()['status'] == 'draft' and r.json()['images'] == []
    assert c.get('/api/v1/products/' + pid).status_code == 404
    assert c.post(f'/api/v1/merchant/products/{pid}/submit', headers=auth).status_code == 409


def test_photo_classification_http_and_conflict(env, monkeypatch):
    c, auth, _, _, _, factory, _ = setup(env)
    pid = c.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
           files={'files': ('image.jpg', photo(), 'image/jpeg')})
    with factory() as db:
        image = db.get(Product, pid).images[0]
        db.add(ImageMLEmbedding(image_id=image.id, model_id=MODEL_ID, embedding=[1.0]+[0.0]*(DIM-1)))
        db.commit()
    monkeypatch.setattr(ci, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(ci, 'photo_vote', lambda vector: ('Обувь', .38, True))
    url = f'/api/v1/merchant/products/{pid}/classify'
    r = c.post(url, headers=auth)
    assert r.status_code == 200, r.text
    assert r.json()['category'] == 'Обувь'
    assert r.json()['category_inference']['source'] == 'photo'
    r = c.put(f'/api/v1/merchant/products/{pid}', headers=auth,
               json={'title': 'Сумка', 'category': 'Обувь'})
    assert r.json()['category'] == 'Без категории'
    assert r.json()['category_inference']['status'] == 'conflict'
    monkeypatch.setattr(ci, 'photo_vote', lambda vector: (_ for _ in ()).throw(RuntimeError('offline')))
    r = c.post(url, headers=auth)
    assert r.status_code == 200
    assert r.json()['category_inference']['status'] == 'model_unavailable'


def test_photo_score_abstains_and_manual_category_survives(env, monkeypatch):
    # The real model is separately smoke-tested when available. Here exact vectors
    # make threshold behavior deterministic instead of claiming model accuracy.
    monkeypatch.setattr(ci, 'text_vectors', lambda: [('Обувь', [1.0]+[0.0]*(DIM-1)),
                                                   ('_other', [0.0, 1.0]+[0.0]*(DIM-2))])
    assert ci.photo_vote([1.0]+[0.0]*(DIM-1))[2]
    assert not ci.photo_vote([.71, .70]+[0.0]*(DIM-2))[2]
    assert not ci.photo_vote([0.0, 1.0]+[0.0]*(DIM-2))[2]
    c, auth, _, _, _, _, _ = setup(env)
    pid = c.post('/api/v1/merchant/products', headers=auth,
                 json={'title': 'Куртка', 'category': 'Одежда'}).json()['id']
    monkeypatch.setattr(ci, 'SEARCH_BACKEND', 'clip')
    r = c.post(f'/api/v1/merchant/products/{pid}/classify', headers=auth)
    assert r.json()['category'] == 'Одежда'
    assert r.json()['category_inference']['source'] == 'manual'
