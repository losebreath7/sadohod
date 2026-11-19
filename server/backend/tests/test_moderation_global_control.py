"""API regression tests for proactive moderation."""
from sqlalchemy import select
from backend.app.account import Buyer
from backend.app.moderation_enforcement_models import AccountRestriction, ShopRestriction, ModerationEmail
from backend.app.moderation_models import ModerationAction
from test_account import setup, login
from test_moderation_workspace import provision
from test_merchant_v080 import env
from test_product_safety import publish


def test_staff_can_block_account_and_notify(setup, monkeypatch):
    c, codes, factory = setup
    auth = login(c, codes, 'control-user@example.com')
    _, _, _, staff = provision(c, monkeypatch, username='global-control-user')
    found = c.get('/api/v1/moderation/control/search?kind=accounts&q=control-user', headers=staff)
    assert found.status_code == 200
    uid = found.json()['items'][0]['id']
    url = '/api/v1/moderation/control/accounts/' + uid
    assert c.post(url, json={'action': 'block', 'reason': 'Нарушение правил'}).status_code == 401
    result = c.post(url, headers=staff, json={'action': 'block', 'reason': 'Нарушение правил'})
    assert result.status_code == 200, result.text
    assert c.get('/api/v1/account', headers=auth).status_code == 401
    assert c.post('/api/v1/auth/code', json={'email':'control-user@example.com'}).status_code == 403
    assert c.post(url, headers=staff, json={'action': 'block', 'reason': 'Повтор'}).status_code == 409
    with factory() as db:
        assert db.get(AccountRestriction, uid).active
        assert db.scalar(select(ModerationEmail).where(ModerationEmail.recipient == 'control-user@example.com'))
        assert db.scalar(select(ModerationAction).where(ModerationAction.target_id == uid))
    restored = c.post(url, headers=staff, json={'action': 'unblock', 'reason': 'Решение пересмотрено'})
    assert restored.status_code == 200, restored.text


def test_moderator_can_hide_any_published_product(env, monkeypatch):
    c, codes, auth, pavilion, pid = publish(env, 'control-product@example.com')
    _, _, _, staff = provision(c, monkeypatch, username='global-control-product')
    url = '/api/v1/moderation/control/products/' + pid
    hidden = c.post(url, headers=staff, json={'action': 'hide', 'reason': 'Нарушение правил'})
    assert hidden.status_code == 200, hidden.text
    assert c.get('/api/v1/products/' + pid).status_code == 404
    with env[2]() as db:
        assert db.scalar(select(ModerationEmail).where(ModerationEmail.recipient == 'control-product@example.com'))
    restored = c.post(url, headers=staff, json={'action': 'restore', 'reason': 'Решение пересмотрено'})
    assert restored.status_code == 200, restored.text
    assert c.get('/api/v1/products/' + pid).status_code == 404


def test_moderator_can_block_shop_and_cut_off_offers(env, monkeypatch):
    c, codes, auth, pavilion, pid = publish(env, 'control-shop@example.com')
    _, _, _, staff = provision(c, monkeypatch, username='global-control-shop')
    rows = c.get('/api/v1/moderation/control/search?kind=shops', headers=staff).json()['items']
    sid = next(x['id'] for x in rows if x['subtitle'] == 'control-shop@example.com')
    url = '/api/v1/moderation/control/shops/' + sid
    result = c.post(url, headers=staff, json={'action': 'block', 'reason': 'Нарушение правил'})
    assert result.status_code == 200, result.text
    assert c.get('/api/v1/products/' + pid).status_code == 404
    assert c.get('/api/v1/merchant/products', headers=auth).status_code == 403
    with env[2]() as db:
        assert db.get(ShopRestriction, sid).active
    result = c.post(url, headers=staff, json={'action': 'unblock', 'reason': 'Решение пересмотрено'})
    assert result.status_code == 200, result.text

def test_staff_can_hide_review_without_report(setup, monkeypatch):
    from backend.app.models import Pavilion, Seller
    from backend.app.buyer_reviews_v082 import SellerReview
    c, codes, factory = setup
    login(c, codes, 'control-review@example.com')
    with factory() as db:
        buyer = db.scalar(select(Buyer).where(Buyer.email == 'control-review@example.com'))
        db.add(Pavilion(id='control-review-pav', zone='В', code='91'))
        db.flush()
        db.add(Seller(id='control-review-shop', name='Магазин',
                      pavilion_id='control-review-pav'))
        db.flush()
        db.add(SellerReview(id='control-review-id', buyer=buyer.id,
                            seller='control-review-shop', rating=4,
                            text='Проверяемый отзыв', moderation_status='approved'))
        db.commit()
    _, _, _, staff = provision(c, monkeypatch, username='global-control-review')
    url = '/api/v1/moderation/control/reviews/control-review-id'
    assert c.post(url, headers=staff,
                  json={'action':'hide','reason':'Нарушение правил отзывов'}).status_code == 200
    assert c.get('/api/v1/sellers/control-review-shop/reviews').json()['count'] == 0
    assert c.post(url, headers=staff,
                  json={'action':'restore','reason':'Жалоба не подтвердилась'}).status_code == 200
    assert c.get('/api/v1/sellers/control-review-shop/reviews').json()['count'] == 1

def test_mail_outbox_dispatch_and_retry(setup, monkeypatch):
    from backend.app import moderation_email
    from backend.app.moderation_enforcement_models import ModerationEmail
    import time
    c, codes, factory = setup
    recipients = []
    with factory() as db:
        db.add(ModerationEmail(id='mail-one', recipient='notify@example.com',
            subject='Решение', body='Причина', status='pending',
            attempts=0, next_attempt_at=time.time(), created_at=time.time()))
        db.commit()
    def failure(item):
        raise OSError('smtp unavailable')
    monkeypatch.setattr(moderation_email, 'send_message', failure)
    assert moderation_email.dispatch_due(factory) == 0
    with factory() as db:
        row = db.get(ModerationEmail, 'mail-one')
        assert row.status == 'pending' and row.attempts == 1
        row.next_attempt_at = time.time()-1
        db.commit()
    monkeypatch.setattr(moderation_email, 'send_message',
                        lambda item: recipients.append(item.recipient))
    assert moderation_email.dispatch_due(factory) == 1
    assert recipients == ['notify@example.com']
    with factory() as db:
        row = db.get(ModerationEmail, 'mail-one')
        assert row.status == 'sent' and row.attempts == 2 and row.sent_at is not None
