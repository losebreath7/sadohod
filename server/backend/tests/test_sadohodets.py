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
    assert c.post(base, headers=a, json={'name':'Пустая', 'product_id':'unknown'}).status_code == 404
    assert c.get(base, headers=a).json()['items'] == []
    quick = c.post(base, headers=a, json={'name':'Один шаг','product_id':'folder-product'})
    assert quick.status_code == 201
    assert c.get(base+'/'+quick.json()['id'],headers=a).json()['items'][0]['product_id'] == 'folder-product'
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
    assert c.patch(item, headers=a, json={'note':'две, размер М'}).json()['collected']
    assert c.put(item, headers=a).json()['added'] is False
    assert c.get(first, headers=a).json()['items'][0]['note'] == 'две, размер М'
    assert c.get(second, headers=a).json()['items'][0]['note'] == ''
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


def test_directory_and_moderated_reviews(setup, monkeypatch):
    c, codes, sessions = setup
    monkeypatch.setenv('ADMIN_TOKEN', 'courier-test-admin')
    a = login(c, codes, 'directory-a@example.com')
    b = login(c, codes, 'directory-b@example.com')
    for headers, name in ((a, 'Анна'), (b, 'Борис')):
        r = c.put(ROOT, headers=headers, json={'name': name, 'contacts': {'phone': '+79991234567'}})
        assert r.status_code == 200, r.text
    pid = c.get(ROOT, headers=a).json()['id']
    bid = c.get(ROOT, headers=b).json()['id']
    base = '/api/v1/sadohodets'
    assert c.get(base).json()['items'] == []
    assert c.get(base+'/'+pid).status_code == 404
    for headers in (a, b):
        assert c.put(ROOT+'/publication', headers=headers, json={'published': True}).status_code == 200
    review = base+'/'+pid+'/my-review'
    assert c.put(review, headers=a, json={'rating': 5}).status_code == 403
    assert c.put(review, headers=b, json={'rating': 6}).status_code == 422
    r = c.put(review, headers=b, json={'rating': 5, 'text': 'Спасибо'})
    assert r.status_code == 200, r.text
    assert c.get(base+'/'+pid).json()['rating'] is None
    admin = {'Authorization': 'Bearer courier-test-admin'}
    path = base+'/admin/reviews/'+pid+'/'+bid
    assert c.put(path, headers=b, json={'status': 'approved'}).status_code == 401
    assert c.put(path, headers=admin, json={'status': 'approved'}).status_code == 200
    assert c.get(base).json()['items'][0]['id'] == pid
    assert c.get(base+'?min_rating=5').json()['items'][0]['review_count'] == 1
    assert c.get(base+'/'+pid+'/reviews').json()['items'][0]['rating'] == 5
    assert c.put(review, headers=b, json={'rating': 4}).status_code == 200
    assert c.get(base+'/'+pid+'/reviews').json()['items'] == []
    assert c.delete(review, headers=b).status_code == 200
    assert c.put(ROOT+'/publication', headers=a, json={'published': False}).status_code == 200
    assert c.get(base+'/'+pid).status_code == 404


def test_profile_media_publication_boundary(setup):
    import base64
    import io
    from PIL import Image
    c, codes, sessions = setup
    a = login(c, codes, 'media-courier@example.com')
    assert c.put(ROOT, headers=a, json={'name': 'Анна', 'contacts': {'phone': '+79991234567'}}).status_code == 200
    buf = io.BytesIO()
    Image.new('RGB', (12, 12), 'red').save(buf, format='PNG')
    data = base64.b64encode(buf.getvalue()).decode()
    r = c.put(ROOT+'/media/avatar', headers=a, json={'data': data})
    assert r.status_code == 200, r.text
    public = r.json()['avatar']
    assert c.get(public).status_code == 404
    assert c.get(ROOT+'/media/avatar', headers=a).headers['content-type'] == 'image/jpeg'
    assert c.put(ROOT+'/publication', headers=a, json={'published': True}).status_code == 200
    assert c.get(public).status_code == 200
    assert c.delete(ROOT+'/media/avatar', headers=a).status_code == 200
    assert c.get(public).status_code == 404
