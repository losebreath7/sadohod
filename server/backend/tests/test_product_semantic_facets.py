"""End-to-end multi-facet catalog search without inventing photo accuracy.

Model votes are mocked so these tests validate indexing/search/legacy
compatibility. A separate labelled real-photo benchmark is required for the
OpenCLIP checkpoint before claiming production recognition precision.
"""
from sqlalchemy import select
from backend.app import category_inference
from backend.app.models import ProductImage, ImageMLEmbedding, Product
from backend.app.ml_clip import MODEL_ID
from backend.app.merchant_models import ProductCategoryAssignment, ProductSearchTag
from backend.app.product_semantics import query_terms, category_facets
from backend.app.text_search import matched_category_ids
from test_merchant_v080 import env, applicant, admin_client, login, approve, photo


def _published_unnamed(env, title=''):
    c, codes, factory, _ = env
    auth = login(c, codes, 'search-facets@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "facets", auth)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    p = c.post('/api/v1/merchant/products', headers=auth, json={'title': title})
    assert p.status_code == 201, p.text
    pid = p.json()['id']
    uploaded = c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
         files={'files': ('photo.jpg', photo(), 'image/jpeg')})
    assert uploaded.status_code == 201, uploaded.text
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
        json={'title': title, 'request_id': 'search-facets-save-123',
              'submit': True, 'listings': [
                  {'pavilion_id': pavilion, 'price': 800,
                   'sale_modes': ['retail']}]})
    assert saved.status_code == 200, saved.text
    with factory() as db:
        im = db.scalar(select(ProductImage).where(ProductImage.product_id == pid))
        db.add(ImageMLEmbedding(image_id=im.id, model_id=MODEL_ID,
                                embedding=[0.0]*511+[1.0]))
        db.commit()
    return c, factory, pid


def _reclassify(factory, monkeypatch, broad, leaf, species=None):
    monkeypatch.setattr(category_inference, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(category_inference, 'photo_vote',
                        lambda vector: (broad, .47, True))
    monkeypatch.setattr(category_inference, 'toy_leaf_vote',
                        lambda vector: leaf if broad == 'Игрушки' else None)
    monkeypatch.setattr(category_inference, 'visual_leaf_vote',
                        lambda vector: leaf)
    monkeypatch.setattr(category_inference, 'toy_object_vote',
                        lambda vector: species)
    with factory() as db:
        return category_inference.reclassify_indexed_products(db)


def test_nameless_monkey_is_searchable_by_hierarchy_and_synonyms(env, monkeypatch):
    c, factory, pid = _published_unnamed(env)
    _reclassify(factory, monkeypatch, 'Игрушки', 'toys-plush', 'обезьяна')
    detail = c.get(f'/api/v1/products/{pid}').json()
    assert detail['title'] == 'Без названия'
    assert detail['category_id'] == 'toys-plush'
    assert 'обезьяна' in detail['search_tags']
    assert 'мягкая игрушка' in detail['search_tags']
    for phrase in ('игрушка', 'мягкая игрушка', 'обезьяна', 'обезяна', 'мартышка'):
        found = c.get('/api/v1/search/text', params={'q': phrase})
        assert found.status_code == 200, found.text
        assert pid in {row['id'] for row in found.json()['items']}, phrase
        filtered = c.get('/api/v1/products', params={'q': phrase})
        assert pid in {row['id'] for row in filtered.json()['items']}, phrase
    with factory() as db:
        assert category_inference.reclassify_indexed_products(db) == 0
        assert len(db.scalars(select(ProductSearchTag).where(
            ProductSearchTag.product_id == pid)).all()) == len(detail['search_tags'])


def test_nameless_ring_found_by_name_and_legacy_category(env, monkeypatch):
    c, factory, pid = _published_unnamed(env)
    _reclassify(factory, monkeypatch, 'Украшения', 'jewelry-rings')
    detail = c.get(f'/api/v1/products/{pid}').json()
    assert detail['category_id'] == 'jewelry-rings'
    for q in ('кольцо', 'кольца', 'украшение'):
        results = c.get('/api/v1/search/text', params={'q': q}).json()
        assert pid in {p['id'] for p in results['items']}, q


def test_nameless_skirt_found_by_name_and_category(env, monkeypatch):
    c, factory, pid = _published_unnamed(env)
    _reclassify(factory, monkeypatch, 'Одежда', 'clothing-skirts')
    detail = c.get(f'/api/v1/products/{pid}').json()
    assert detail['category_id'] == 'clothing-skirts'
    assert pid in {p['id'] for p in c.get('/api/v1/search/text',
                                         params={'q': 'юбка'}).json()['items']}
    assert pid in {p['id'] for p in c.get('/api/v1/products',
                                         params={'category': 'clothing-skirts'}).json()['items']}


def test_named_animal_motif_is_not_a_toy(env, monkeypatch):
    c, factory, pid = _published_unnamed(env, title='Футболка с принтом обезьяна')
    _reclassify(factory, monkeypatch, 'Одежда', 'clothing-tshirts')
    tags = c.get(f'/api/v1/products/{pid}').json()['search_tags']
    assert 'обезьяна' not in tags
    assert pid not in {p['id'] for p in c.get('/api/v1/products',
                                             params={'category': 'toys'}).json()['items']}


def test_titled_plush_monkey_is_searchable_even_without_clip(env):
    c, codes, factory, _ = env
    auth = login(c, codes, 'title-species@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "title-species", auth)}/decision')
    created = c.post('/api/v1/merchant/products', headers=auth,
                     json={'title': 'Мягкая игрушка обезьяна'})
    assert created.status_code == 201
    pid = created.json()['id']
    detail = c.get(f'/api/v1/merchant/products/{pid}', headers=auth).json()
    assert detail['category'] == 'Игрушки'
    with factory() as db:
        tags = {row.tag for row in db.scalars(select(ProductSearchTag).where(
            ProductSearchTag.product_id == pid))}
        assert 'обезьяна' in tags
        assert 'игрушка' in tags


def test_category_and_synonym_helpers_are_canonical():
    assert query_terms('обезяна') == {'обезяна', 'обезьяна'}
    assert 'обезьяна' in query_terms('мартышка')
    assert 'кольцо' in query_terms('кольца')
    assert 'юбка' in query_terms('юбки')
    assert 'toys-plush' in matched_category_ids('мягкая игрушка')
    tags = category_facets('toys-plush')
    assert 'игрушки' in tags and 'мягкая игрушка' in tags


def test_multi_image_consensus_ignores_unrecognised_photos():
    from backend.app.category_inference import consensus_winner

    # One properly recognised photo is sufficient when other images abstain.
    # The caller does not add an abstaining image to the vote list.
    assert consensus_winner([('jewelry-rings', .47)]) == 'jewelry-rings'
    assert consensus_winner([('jewelry-rings', .47), ('jewelry-rings', .40)]) == 'jewelry-rings'
    assert consensus_winner([('jewelry-rings', .47), ('clothing-skirts', .45)]) is None
    assert consensus_winner([]) is None


def test_ring_and_phone_case_canonical_search_words():
    from backend.app.product_semantics import category_facets, query_terms

    assert 'кольцо' in category_facets('jewelry-rings')
    assert 'чехол для телефона' in category_facets('electronics-phone')
    assert 'кольцо' in query_terms('кольца')
    assert 'чехол для телефона' in query_terms('чехлы для телефона')


def test_admin_can_audit_missing_classification_without_mutation(env):
    client, factory, pid = _published_unnamed(env)
    response = client.get('/api/v1/admin/merchant/catalog/classification-audit',
                          params={'product_id': pid})
    assert response.status_code == 200, response.text
    report = response.json()
    assert report['total'] == 1
    assert report['missing_categories'] == 1
    assert report['missing_search_tags'] == 1
    assert report['examples'][0]['product_id'] == pid
    # Audit must not change the offer or synthesize a category.
    detail = client.get(f'/api/v1/products/{pid}').json()
    assert detail['category_id'] is None
    assert detail['search_tags'] == []


def test_real_published_search_survives_two_abstaining_images(env, monkeypatch):
    """Regression: one clear photo + two weak photos still indexes 'кольцо'."""
    c, factory, pid = _published_unnamed(env)
    with factory() as db:
        first = db.scalar(select(ProductImage).where(ProductImage.product_id == pid))
        for index in (2, 3):
            iid = f'weak-{index}-' + pid[:20]
            db.add(ProductImage(id=iid, product_id=pid,
                                filename=first.filename, descriptor=first.descriptor))
            # The embedding's FK requires the new photo row to exist first.
            db.flush()
            db.add(ImageMLEmbedding(image_id=iid, model_id=MODEL_ID,
                                    embedding=[0.0]*511+[float(index)]))
        db.commit()
    monkeypatch.setattr(category_inference, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(category_inference, 'photo_vote',
                        lambda vector: ('Украшения', .47, True)
                        if vector[-1] == 1.0 else ('_other', .12, False))
    monkeypatch.setattr(category_inference, 'visual_leaf_vote',
                        lambda vector: 'jewelry-rings' if vector[-1] == 1.0 else None)
    with factory() as db:
        category_inference.reclassify_indexed_products(db)
    detail = c.get(f'/api/v1/products/{pid}').json()
    assert detail['category_id'] == 'jewelry-rings'
    assert 'кольцо' in detail['search_tags']
    found = c.get('/api/v1/search/text', params={'q': 'кольцо'}).json()
    assert pid in {row['id'] for row in found['items']}


@__import__('pytest').mark.parametrize('word', [
    'кольцо', 'браслет', 'чехол для телефона', 'настольная игра', 'парфюм',
])
def test_buyer_search_finds_unnamed_unclassified_item_via_visual_index(
    env, monkeypatch, word
):
    """Public API fallback must work even if the category vote abstained."""
    from backend.app import api, ml_clip, search

    client, factory, pid = _published_unnamed(env)
    with factory() as db:
        image_id = db.scalar(select(ProductImage.id).where(
            ProductImage.product_id == pid))
    # Exercise the real HTTP search merge and the multi-prompt retrieval;
    # only ML text encoding and pgvector scoring are mocked.
    monkeypatch.setattr(api, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(ml_clip, 'embed_text', lambda prompt: [1.0] * 512)
    monkeypatch.setattr(search, 'ranked_images',
                        lambda session, query, limit, model_id:
                        [(image_id, .32)])
    response = client.get('/api/v1/search/text', params={'q': word})
    assert response.status_code == 200, response.text
    ids = [item['id'] for item in response.json()['items']]
    assert ids == [pid], (word, ids)
