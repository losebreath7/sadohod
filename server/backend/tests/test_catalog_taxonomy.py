"""Category hierarchy, conservative classification and buyer search regression."""
import pytest
from backend.app.catalog_taxonomy import (
    NODES_V1, BY_ID, category_path, descendant_ids, resolve_leaf,
)
from test_merchant_v080 import env, applicant, login, approve, admin_client, photo


@pytest.mark.parametrize('title,expected', [
    ('Кукла Барби', 'toys-dolls'),
    ('женские кроссовки', 'shoes-women-sneakers'),
    ('Кроссовки мужские 42', 'shoes-men-sneakers'),
    ('Кроссовки детские', 'shoes-kids-sneakers'),
    ('Куртка детская', 'clothing-kids-jackets'),
    ('Крем для лица', 'beauty-face-cream'),
    ('Кастрюля большая', 'home-pots'),
    ('Чехол для куклы', None),
    ('Сумка с принтом кукла', None),
    ('Куртка и сумка', None),
    ('Артикул 123', None),
    ('', None),
])
def test_rules_are_specific_and_abstain_on_ambiguous_titles(title, expected):
    assert resolve_leaf(title) == expected


def test_tree_uses_stable_ids_and_complete_ancestor_paths():
    assert len(NODES_V1) >= 80
    assert len(BY_ID) == len(NODES_V1)
    assert len(set(BY_ID)) == len(NODES_V1)
    for node_id, parent, _ in NODES_V1:
        assert parent is None or parent in BY_ID
        path = category_path(node_id)
        assert path[-1]['id'] == node_id
        assert len(path) == len({entry['id'] for entry in path})
    assert [part['name'] for part in category_path('toys-dolls')] == [
        'Игрушки', 'Детские игрушки', 'Куклы']
    assert 'toys-dolls' in descendant_ids('toys')
    assert 'toys-dolls' in descendant_ids('toys-kids')
    assert 'toys-dolls' not in descendant_ids('shoes')


def test_doll_is_auto_classified_and_found_in_all_parent_categories(env):
    c, codes, _, _ = env
    auth = login(c, codes, 'taxonomy-doll@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "taxonomy-1", auth)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    created = c.post('/api/v1/merchant/products', headers=auth, json={'title': 'Кукла Барби'})
    assert created.status_code == 201, created.text
    pid = created.json()['id']
    assert created.json()['category'] == 'Игрушки'
    assert c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                  files={'files': ('doll.jpg', photo(), 'image/jpeg')}).status_code == 201
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
                  json={'title': 'Кукла Барби', 'request_id': 'doll-save-123',
                        'listings': [{'pavilion_id': pavilion, 'price': 500,
                                      'sale_modes': ['retail']}], 'submit': True})
    assert saved.status_code == 200, saved.text
    detail = c.get(f'/api/v1/products/{pid}')
    assert detail.status_code == 200, detail.text
    assert detail.json()['category_id'] == 'toys-dolls'
    assert [node['name'] for node in detail.json()['category_path']] == [
        'Игрушки', 'Детские игрушки', 'Куклы']
    for category in ('toys', 'toys-kids', 'toys-dolls', 'Игрушки'):
        found = c.get('/api/v1/products', params={'category': category})
        assert found.status_code == 200, found.text
        assert pid in {item['id'] for item in found.json()['items']}
    assert pid not in {
        item['id'] for item in
        c.get('/api/v1/products', params={'category': 'shoes'}).json()['items']
    }
    tree = c.get('/api/v1/categories/tree').json()['items']
    assert next(item for item in tree if item['id'] == 'toys-dolls')['parent_id'] == 'toys-kids'


def test_unknown_product_publishes_without_invented_leaf(env):
    c, codes, _, _ = env
    auth = login(c, codes, 'taxonomy-unknown@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "taxonomy-2", auth)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    pid = c.post('/api/v1/merchant/products', headers=auth,
                 json={'title': 'Артикул 123'}).json()['id']
    c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
           files={'files': ('unknown.jpg', photo(), 'image/jpeg')})
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
                  json={'title': 'Артикул 123', 'request_id': 'unknown-save-123',
                        'listings': [{'pavilion_id': pavilion,
                                      'sale_modes': ['retail']}], 'submit': True})
    assert saved.status_code == 200, saved.text
    detail = c.get(f'/api/v1/products/{pid}').json()
    assert detail['category_id'] is None
    assert detail['category_path'] == []
    assert detail['price'] is None
