"""Store-review access: security, non-interference and seller permission checks.

All credentials and emails in this file are synthetic CI fixtures.
"""
import sys
import time
from pathlib import Path
from sqlalchemy import select
from backend.app import account as auth
from backend.app.models import Pavilion, Seller, SellerDetails
from backend.app.merchant_models import PavilionClaim, ShopMembership, ShopRecord
from test_account import setup as account_setup  # noqa: F401

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from manage_review_accounts import provision, revoke, validate_seller


def _verify(client, email, code):
    return client.post('/api/v1/auth/verify', json={'email': email, 'code': code})


def test_review_account_requires_provision_and_regular_otp_unchanged(account_setup):
    client, sent, sessions = account_setup
    # A valid-looking review code never works for an ordinary user.
    assert _verify(client, 'normal@test.invalid', '914273').status_code == 400
    assert client.post('/api/v1/auth/code', json={'email': 'normal@test.invalid'}).status_code == 200
    assert sent.get('normal@test.invalid')
    normal = _verify(client, 'normal@test.invalid', sent['normal@test.invalid'])
    assert normal.status_code == 200
    assert 'code' not in normal.json()
    with sessions() as db:
        provision(db, 'buyer-apple@test.invalid', 'apple', 'buyer', '248913',
                  time.time() + 15 * 86400)
    response = client.post('/api/v1/auth/code', json={'email': 'buyer-apple@test.invalid'})
    assert response.status_code == 200
    assert 'code' not in response.json()
    # Reviewer request deliberately does not send email.
    assert 'buyer-apple@test.invalid' not in sent
    assert _verify(client, 'buyer-apple@test.invalid', '248913').status_code == 200
    # The same review code cannot authenticate another email.
    assert _verify(client, 'normal@test.invalid', '248913').status_code == 400


def test_reviewer_code_is_hashed_and_account_bound(account_setup):
    client, sent, sessions = account_setup
    with sessions() as db:
        provision(db, 'buyer-google@test.invalid', 'google', 'buyer', '517304',
                  time.time() + 5 * 86400)
        reviewer = db.get(auth.ReviewAccess, 'buyer-google@test.invalid')
        assert reviewer.code_digest != '517304'
        assert len(reviewer.code_digest) > 70
        assert reviewer.code_digest.count(':') == 1
        person = db.scalar(select(auth.Buyer).where(
            auth.Buyer.email == 'buyer-google@test.invalid'))
        assert reviewer.buyer_id == person.id
        assert reviewer.platform == 'google' and reviewer.role == 'buyer'
    response = _verify(client, 'buyer-google@test.invalid', '517304')
    assert response.status_code == 200
    token = {'Authorization': 'Bearer ' + response.json()['token']}
    assert client.get('/api/v1/account', headers=token).status_code == 200
    with sessions() as db:
        revoke(db, 'buyer-google@test.invalid')
    assert client.get('/api/v1/account', headers=token).status_code == 401
    assert _verify(client, 'buyer-google@test.invalid', '517304').status_code == 400
    assert client.post('/api/v1/auth/code', json={'email': 'buyer-google@test.invalid'}).status_code == 200
    assert 'buyer-google@test.invalid' not in sent


def test_review_code_expiry_rotation_and_existing_session_revoked(account_setup):
    client, _, sessions = account_setup
    with sessions() as db:
        provision(db, 'buyer-rotation@test.invalid', 'apple', 'buyer', '401238',
                  time.time() + 86400)
    old = _verify(client, 'buyer-rotation@test.invalid', '401238')
    assert old.status_code == 200
    with sessions() as db:
        provision(db, 'buyer-rotation@test.invalid', 'apple', 'buyer', '401239',
                  time.time() + 86400)
    assert client.get('/api/v1/account', headers={
        'Authorization': 'Bearer ' + old.json()['token']
    }).status_code == 401
    assert _verify(client, 'buyer-rotation@test.invalid', '401238').status_code == 400
    assert _verify(client, 'buyer-rotation@test.invalid', '401239').status_code == 200
    with sessions() as db:
        row = db.get(auth.ReviewAccess, 'buyer-rotation@test.invalid')
        row.expires = time.time() - 1
        db.commit()
    assert _verify(client, 'buyer-rotation@test.invalid', '401239').status_code == 400


def test_global_review_rate_limit_and_lifetime_lock(account_setup):
    client, _, sessions = account_setup
    with sessions() as db:
        provision(db, 'limited@test.invalid', 'google', 'buyer', '609812',
                  time.time() + 86400)
    for _ in range(5):
        assert _verify(client, 'limited@test.invalid', '000000').status_code == 400
    # Even the correct reusable code is throttled after 5 attempts per hour.
    assert _verify(client, 'limited@test.invalid', '609812').status_code == 429
    with sessions() as db:
        account = db.get(auth.ReviewAccess, 'limited@test.invalid')
        assert account.failed_total == 5
        # Simulate 20 lifetime failures without spending hours in CI.
        account.failed_total = 20
        db.commit()
    assert _verify(client, 'limited@test.invalid', '609812').status_code in (400, 429)


def test_seller_requires_real_shop_approval_and_pavilion_claim(account_setup):
    client, _, sessions = account_setup
    with sessions() as db:
        provision(db, 'seller-apple@test.invalid', 'apple', 'seller', '723849',
                  time.time() + 30 * 86400)
        assert not validate_seller(db, 'seller-apple@test.invalid')
    response = _verify(client, 'seller-apple@test.invalid', '723849')
    assert response.status_code == 200
    token = {'Authorization': 'Bearer ' + response.json()['token']}
    assert client.get('/api/v1/merchant/me', headers=token).status_code == 200
    assert client.get('/api/v1/merchant/shop', headers=token).status_code == 403
    assert client.get('/api/v1/merchant/products', headers=token).status_code == 403
    with sessions() as db:
        user = db.scalar(select(auth.Buyer).where(auth.Buyer.email == 'seller-apple@test.invalid'))
        db.add(Pavilion(id='test-pavilion-review', zone='Review zone', code='R1'))
        db.flush()
        db.add(Seller(id='test-review-seller', name='Review Store — Test',
                      pavilion_id='test-pavilion-review', details=SellerDetails(
                          contact='Review data only', is_demo=False)))
        db.flush()
        db.add(ShopRecord(seller_id='test-review-seller'))
        db.add(ShopMembership(buyer_id=user.id, seller_id='test-review-seller', role='owner'))
        db.add(PavilionClaim(zone_key='review zone', code_key='r1',
                             seller_id='test-review-seller', pavilion_id='test-pavilion-review'))
        db.commit()
        assert validate_seller(db, 'seller-apple@test.invalid')
    assert client.get('/api/v1/merchant/shop', headers=token).status_code == 200
    pavilions = client.get('/api/v1/merchant/pavilions', headers=token)
    assert pavilions.status_code == 200
    assert len(pavilions.json()['items']) == 1
    other = client.get('/api/v1/merchant/shop')
    assert other.status_code == 401


def test_operator_rejects_elevation_of_existing_customer(account_setup):
    client, sent, sessions = account_setup
    assert client.post('/api/v1/auth/code', json={'email': 'existing@test.invalid'}).status_code == 200
    assert _verify(client, 'existing@test.invalid', sent['existing@test.invalid']).status_code == 200
    with sessions() as db:
        import pytest
        with pytest.raises(ValueError):
            provision(db, 'existing@test.invalid', 'apple', 'seller', '130847',
                      time.time() + 86400)
        db.rollback()
        with pytest.raises(ValueError):
            provision(db, 'other@test.invalid', 'unknown', 'buyer', '130847',
                      time.time() + 86400)
        with pytest.raises(ValueError):
            provision(db, 'other@test.invalid', 'apple', 'buyer', '123',
                      time.time() + 86400)
