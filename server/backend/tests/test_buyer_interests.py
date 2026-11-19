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
