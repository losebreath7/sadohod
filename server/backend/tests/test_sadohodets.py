"""Profile publication, authorization and account deletion regressions."""
from backend.tests.test_account import setup, login  # noqa: F401

ROOT = '/api/v1/sadohodets/me'


def test_profile_lifecycle_and_isolation(setup):
    c, codes, sessions = setup
    a = login(c, codes, 'courier-a@example.com')
    b = login(c, codes, 'courier-b@example.com')
    assert c.get(ROOT).status_code == 401
    assert c.get(ROOT, headers=a).status_code == 404
    r = c.put(ROOT, headers=a, json={'name': 'Анна'})
    assert r.status_code == 200, r.text
    assert not r.json()['published']
    assert c.get(ROOT, headers=b).status_code == 404
    assert c.put(ROOT+'/publication', headers=a, json={'published': True}).status_code == 422
    for contacts in ({'unknown': 'x'}, {'website': 'javascript:alert(1)'}, {'phone': 'abc'}):
        assert c.put(ROOT, headers=a, json={'name': 'Анна', 'contacts': contacts}).status_code == 422
    r = c.put(ROOT, headers=a, json={'name': 'Анна', 'contacts': {'telegram': '@courier_a'}})
    assert r.status_code == 200, r.text
    assert r.json()['contacts']['telegram'] == 'https://t.me/courier_a'
    assert c.put(ROOT+'/publication', headers=a, json={'published': True}).json()['published']
    assert not c.put(ROOT, headers=a, json={'name': 'Анна'}).json()['published']
    assert c.delete(ROOT, headers=a).status_code == 200
    assert c.get('/api/v1/account', headers=a).status_code == 200
    assert c.get(ROOT, headers=a).status_code == 404


def test_full_account_deletion_cleans_profile(setup):
    from backend.app.sadohodets_models import SadohodetsProfile
    c, codes, sessions = setup
    a = login(c, codes, 'courier-delete@example.com')
    r = c.put(ROOT, headers=a, json={'name': 'Анна'})
    assert r.status_code == 200, r.text
    buyer_id = r.json()['id']
    assert c.delete('/api/v1/account', headers=a).status_code == 200
    with sessions() as db:
        assert db.get(SadohodetsProfile, buyer_id) is None


def test_client_folders_isolation_and_independent_collected_state(setup):
    from backend.app.models import Product, ProductDetails
    c, codes, sessions = setup
    a = login(c, codes, 'folder-a@example.com')
    b = login(c, codes, 'folder-b@example.com')
    for headers in (a, b):
        assert c.put(ROOT, headers=headers, json={'name': 'Садоходец'}).status_code == 200
    with sessions() as db:
        db.add(Product(id='folder-product', title='Сумка', category='Сумки', description='', colors=[], is_demo=False))
        db.commit()
    base = ROOT+'/folders'
    ids = []
    for name in ('Клиент А', 'Клиент Б'):
        r = c.post(base, headers=a, json={'name': name, 'note': 'Проверить цвет'})
        assert r.status_code == 201, r.text
        ids.append(r.json()['id'])
    first, second = [base+'/'+i for i in ids]
    assert c.get(base, headers=b).json()['items'] == []
    assert c.get(first, headers=b).status_code == 404
    assert c.put(first, headers=b, json={'name': 'Чужая'}).status_code == 404
    assert c.delete(first, headers=b).status_code == 404
    for path in (first, second):
        assert c.put(path+'/items/folder-product', headers=a).status_code == 200
    item = first+'/items/folder-product'
    assert c.patch(item, headers=b, json={'collected': True}).status_code == 404
    assert c.patch(item, headers=a, json={'collected': True}).json()['collected']
    assert c.put(item, headers=a).json()['collected']
    assert len(c.get(first, headers=a).json()['items']) == 1
    assert not c.get(second, headers=a).json()['items'][0]['collected']
    assert c.put(first+'/items/missing', headers=a).status_code == 404
    with sessions() as db:
        db.add(ProductDetails(product_id='folder-product', active=False, sizes=[]))
        db.commit()
    hidden = c.get(first, headers=a).json()['items'][0]
    assert hidden['available'] is False and hidden['product'] is None
    assert c.delete(item, headers=a).status_code == 200
    assert c.get(first, headers=a).json()['items'] == []
    assert c.delete(second, headers=a).status_code == 200
    assert c.get(second, headers=a).status_code == 404
    assert c.delete(ROOT, headers=a).status_code == 200
