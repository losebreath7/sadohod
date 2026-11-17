"""Regression: nameless photo products can be found through actual ML results.

The embedding test fakes a confident model output; it verifies the app wiring,
not real-world model recognition accuracy for every photographed object.
"""
from backend.app import api, category_inference
from backend.app.ml_clip import MODEL_ID
from backend.app.models import ProductImage, ImageMLEmbedding
from backend.app.merchant_models import ProductCategoryAssignment
from backend.app.text_search import matched_category_ids, visual_prompt
from test_merchant_v080 import env, login, applicant, approve, admin_client, photo


def publish_unnamed(env):
    c, codes, factory, _ = env
    auth = login(c, codes, 'photo-classifier@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "photo-test", auth)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    p = c.post('/api/v1/merchant/products', headers=auth, json={'title': ''})
    assert p.status_code == 201, p.text
    pid = p.json()['id']
    upload = c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                    files={'files': ('monkey.jpg', photo(), 'image/jpeg')})
    assert upload.status_code == 201, upload.text
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
        json={'title': '', 'request_id': 'photo-monkey-save',
              'submit': True, 'listings': [
                  {'pavilion_id': pavilion, 'price': None,
                   'sale_modes': ['retail']}]})
    assert saved.status_code == 200, saved.text
    return c, factory, pid


def test_taxonomy_query_maps_singular_and_subcategory():
    assert 'toys-plush' in matched_category_ids('игрушка')
    assert matched_category_ids('мягкая игрушка') == ['toys-plush']
    assert 'toys-dolls' not in matched_category_ids('мягкая игрушка')
    assert 'monkey' in visual_prompt('обезьяна')
    assert 'plush' in visual_prompt('мягкая игрушка')
    assert visual_prompt('случайное неизвестное русское слово') == ''


def test_unnamed_product_found_through_semantic_image_search(env, monkeypatch):
    c, factory, pid = publish_unnamed(env)
    assert pid not in {p['id'] for p in
        c.get('/api/v1/search/text', params={'q':'обезьяна'}).json()['items']}
    # A model hit for the nameless toy must make it through the API to buyers.
    monkeypatch.setattr(api, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(api, 'visual_product_ids',
                        lambda session, query, limit: [pid] if query == 'обезьяна' else [])
    result = c.get('/api/v1/search/text', params={'q':'обезьяна'})
    assert result.status_code == 200, result.text
    assert pid in {p['id'] for p in result.json()['items']}
    assert result.json()['ml_enabled'] is True


def test_reindex_backfills_photo_leaf_without_changing_publication(env, monkeypatch):
    c, factory, pid = publish_unnamed(env)
    with factory() as db:
        img = db.query(ProductImage).filter_by(product_id=pid).first()
        db.add(ImageMLEmbedding(image_id=img.id, model_id=MODEL_ID,
                                embedding=[0.0]*511+[1.0]))
        db.commit()
    monkeypatch.setattr(category_inference, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(category_inference, 'photo_vote',
                        lambda vector: ('Игрушки', .41, True))
    monkeypatch.setattr(category_inference, 'toy_leaf_vote',
                        lambda vector: 'toys-plush')
    with factory() as db:
        changed = category_inference.reclassify_indexed_products(db)
        assert changed >= 1
        assert db.get(ProductCategoryAssignment, pid).category_id == 'toys-plush'
        assert category_inference.reclassify_indexed_products(db) == 0
    assert pid in {p['id'] for p in c.get(
        '/api/v1/search/text', params={'q':'игрушка'}).json()['items']}
    assert pid in {p['id'] for p in c.get(
        '/api/v1/search/text', params={'q':'мягкая игрушка'}).json()['items']}
    assert c.get('/api/v1/products/' + pid).status_code == 200


def test_old_products_query_can_filter_by_taxonomy_name(env):
    c, factory, pid = publish_unnamed(env)
    with factory() as db:
        from backend.app.catalog_taxonomy import NODES_V1
        from backend.app.merchant_models import CatalogCategory
        for idx, (id, parent, name) in enumerate(NODES_V1):
            if db.get(CatalogCategory, id) is None:
                db.add(CatalogCategory(id=id, parent_id=parent, name=name, position=idx))
        db.flush()
        db.add(ProductCategoryAssignment(
            product_id=pid, category_id='toys-plush', source='photo'))
        db.commit()
    matched = c.get('/api/v1/products', params={'q': 'игрушка'})
    assert matched.status_code == 200, matched.text
    assert pid in {p['id'] for p in matched.json()['items']}
