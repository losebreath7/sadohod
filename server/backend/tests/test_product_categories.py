import pytest

from backend.app.product_categories import resolve_category, UNASSIGNED
from test_merchant_v080 import env, login, applicant, approve, admin_client, photo


@pytest.mark.parametrize('title,expected', [
    ('Женская куртка зимняя', 'Верхняя одежда'),
    ('КРОССОВКИ размер 42', 'Обувь'),
    ('Платье вечернее', 'Платья'),
    ('Сумка кожаная', 'Сумки'),
    ('Худи oversize', 'Одежда'),
    ('', UNASSIGNED), ('Без названия', UNASSIGNED),
    ('Артикул 123', UNASSIGNED), ('Куртка и сумка', UNASSIGNED),
    ('Чехол для сумки', UNASSIGNED), ('Сумка с принтом кроссовки', UNASSIGNED),
    ('Платьевый материал', UNASSIGNED),
])
def test_conservative_rules(title, expected):
    assert resolve_category(title) == expected


def test_explicit_category_is_preserved():
    assert resolve_category('Куртка', ' Дизайнерская одежда ') == 'Дизайнерская одежда'


def test_new_product_edit_and_patch15_empty_fields(env):
    c, codes, _, _ = env
    auth = login(c, codes, 'categories@test.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "cat-1", auth)}/decision')
    result = c.post('/api/v1/merchant/products', headers=auth,
                    json={'title': 'Куртка женская', 'category': 'Без категории'})
    assert result.status_code == 201, result.text
    product = result.json()
    assert product['category'] == 'Верхняя одежда'
    updated = c.put('/api/v1/merchant/products/' + product['id'], headers=auth,
                    json={'title': 'Куртка зимняя', 'category': product['category']})
    assert updated.status_code == 200
    assert updated.json()['category'] == 'Верхняя одежда'
    empty = c.post('/api/v1/merchant/products', headers=auth, json={})
    assert empty.status_code == 201
    assert empty.json()['title'] == 'Без названия'
    assert empty.json()['category'] == UNASSIGNED
    filled = c.put('/api/v1/merchant/products/' + empty.json()['id'], headers=auth,
                   json={'title': 'Худи', 'category': UNASSIGNED})
    assert filled.status_code == 200
    assert filled.json()['category'] == 'Одежда'


def test_unknown_category_requires_moderator_and_stays_private(env):
    c, codes, _, _ = env
    auth = login(c, codes, 'moderation@test.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "cat-2", auth)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=auth).json()['items'][0]['id']
    pid = c.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    assert c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                  files={'files': ('image.jpg', photo(), 'image/jpeg')}).status_code == 201
    assert c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
                  json={'pavilion_id': pavilion, 'price': 1000, 'sale_modes': ['retail']}).status_code == 201
    assert c.post(f'/api/v1/merchant/products/{pid}/submit', headers=auth).status_code == 200
    url = f'/api/v1/admin/merchant/products/{pid}/decision'
    for category in (None, '', 'Без категории'):
        body = {'decision': 'approved'}
        if category is not None:
            body['category'] = category
        assert c.post(url, json=body).status_code == 409
        assert c.get('/api/v1/products/' + pid).status_code == 404
        assert c.get(f'/api/v1/merchant/products/{pid}', headers=auth).json()['status'] == 'pending'
    result = c.post(url, json={'decision': 'approved', 'category': 'Сумки'})
    assert result.status_code == 200, result.text
    assert c.get('/api/v1/products/' + pid).json()['category'] == 'Сумки'
