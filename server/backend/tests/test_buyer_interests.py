"""Personal tag ranking and authenticated category tracking regressions."""
from collections import Counter
from sqlalchemy import select
from backend.app.buyer_interests import selected_tags
from backend.app.buyer_interests_models import BuyerCategoryInterest
from backend.app.catalog_taxonomy import BY_ID
from backend.app.account import Buyer
from test_merchant_v080 import env
from test_product_safety import publish
from test_moderation_workspace import provision


def test_preferred_and_related_tags_with_exploration():
    available = Counter({
        'clothing': 15, 'clothing-tshirts': 9,
        'clothing-hoodies': 6, 'shoes': 7, 'beauty': 4,
        'beauty-shampoo': 3, 'home': 5, 'home-decor': 2,
    })
    scores = {'clothing-tshirts': 20, 'clothing': 18, 'shoes': 8}
    tags = selected_tags(available, scores, 'buyer-one', day=21000)
    assert len(tags) == 5
    assert tags[0]['id'] == 'clothing-tshirts'
    assert len({x['name'] for x in tags}) == len(tags)
    assert all(x['id'] in available for x in tags)
    assert all(x['name'] == BY_ID[x['id']][2] for x in tags)
    assert tags == selected_tags(available, scores, 'buyer-one', day=21000)


def test_cold_start_uses_only_available_default_categories():
    available = Counter({'clothing-trousers': 2, 'shoes': 3,
                         'beauty': 1, 'home': 4, 'toys': 1})
    tags = selected_tags(available, {}, 'new-buyer', day=21000)
    assert tags[0]['id'] == 'clothing-trousers'
    assert len(tags) == 5
    assert {x['id'] for x in tags} == set(available)


def test_view_requires_account_and_published_product(env):
    client, codes, seller, pavilion, pid = publish(env, 'interested@example.com')
    endpoint = '/api/v1/account/interests/view'
    assert client.post(endpoint, json={'product_id': pid}).status_code == 401
    recorded = client.post(endpoint, headers=seller, json={'product_id': pid})
    assert recorded.status_code == 200, recorded.text
    assert recorded.json()['tracked'] is True
    assert client.post(endpoint, headers=seller,
        json={'product_id': 'missing'}).status_code == 404
    listed = client.get('/api/v1/account/interests/tags', headers=seller)
    assert listed.status_code == 200, listed.text
    assert listed.json()['items']
    with env[2]() as db:
        rows = db.scalars(select(BuyerCategoryInterest)).all()
        assert len(rows) == 1
        assert rows[0].views == 1
        assert rows[0].buyer_id == db.scalar(
            select(Buyer.id).where(Buyer.email == 'interested@example.com'))


def test_daily_view_count_is_capped(env):
    client, codes, seller, pavilion, pid = publish(env, 'interest-limit@example.com')
    endpoint = '/api/v1/account/interests/view'
    for _ in range(15):
        assert client.post(endpoint, headers=seller,
            json={'product_id': pid}).status_code == 200
    with env[2]() as db:
        rows = db.scalars(select(BuyerCategoryInterest)).all()
        assert len(rows) == 1
        assert rows[0].views == 12


def test_skirts_search_and_favorites_rank_above_generic_clothing(env):
    """Reported journey: search skirts, open product, save it, return home."""
    from test_merchant_v080 import login, admin_client, applicant, approve, make_published
    from backend.app.models import Product
    from backend.app.buyer_interests import category_for
    c, codes, factory, _ = env
    seller = login(c, codes, 'skirt-seller@example.com')
    buyer = login(c, codes, 'skirt-buyer@example.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c, "77", seller)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=seller).json()['items'][0]['id']
    pid = make_published(c, seller, pavilion, title='Юбка миди')
    with factory() as db:
        item = db.get(Product, pid)
        assert category_for(db, item) == 'clothing-skirts'

    search = c.get('/api/v1/search/text?q=%D1%8E%D0%B1%D0%BA%D0%B8')
    assert search.status_code == 200 and pid in [p['id'] for p in search.json()['items']]
    endpoint = '/api/v1/account/interests/search'
    assert c.post(endpoint, json={'query': 'юбки'}).status_code == 401
    for _ in range(3):
        response = c.post(endpoint, headers=buyer, json={'query': 'юбки'})
        assert response.status_code == 200 and response.json()['tracked'] is True
    for _ in range(2):
        assert c.post('/api/v1/account/interests/view', headers=buyer,
                      json={'product_id': pid}).status_code == 200
    fav = c.post('/api/v1/account/favorite', headers=buyer,
                 json={'kind':'product','id':pid,'saved':True})
    assert fav.status_code == 200, fav.text
    tags = c.get('/api/v1/account/interests/tags', headers=buyer)
    assert tags.status_code == 200, tags.text
    assert tags.json()['items'][0]['name'] == 'Юбки', tags.json()
    assert any(x['id'] != 'clothing-skirts' for x in tags.json()['items'][1:])


def test_search_ignores_unrecognized_and_unavailable_categories(env):
    c, codes, factory, _ = env
    buyer = login(c, codes, 'search-limited@example.com')
    url = '/api/v1/account/interests/search'
    assert c.post(url, headers=buyer, json={'query':'несуществующая категория'}).json() == {'tracked':False}
    assert c.post(url, headers=buyer, json={'query':'юбки'}).json() == {'tracked':False}
    with factory() as db:
        assert db.query(BuyerCategoryInterest).count() == 0


def test_generic_parent_must_not_displace_direct_skirts_interest():
    available = Counter({'clothing':20, 'clothing-women':15, 'clothing-skirts':7,
                         'clothing-dresses':8, 'home':4,'beauty':3,'shoes':6})
    inherited = {'clothing':15,'clothing-women':15,'clothing-skirts':15}
    direct = {'clothing-skirts':15}
    result = selected_tags(available, inherited, 'skirt-buyer', day=21000,
                           direct_scores=direct)
    assert result[0] == {'id':'clothing-skirts','name':'Юбки'}
    assert len(result) == 5
