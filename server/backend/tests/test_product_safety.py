"""Buyer complaints and enforceable staff takedown without new seller moderation."""
from backend.app.moderation_models import ModerationAction
from backend.app.product_safety import ProductReport, ProductSafetyHold
from backend.app.seller_notifications import SellerNotification
from test_merchant_v080 import env, login, applicant, approve, admin_client, photo
from test_moderation_workspace import provision


def publish(env, address='safety@example.com'):
    c, codes, _, _ = env
    seller = login(c, codes, address)
    admin_client(c)
    approve(c, f'applications/{applicant(c, "safe-1", seller)}/decision')
    pavilion = c.get('/api/v1/merchant/pavilions', headers=seller).json()['items'][0]['id']
    pid = c.post('/api/v1/merchant/products', headers=seller,
                 json={'title': 'Кукла'}).json()['id']
    upload = c.post(f'/api/v1/merchant/products/{pid}/images', headers=seller,
                    files={'files': ('doll.jpg', photo(), 'image/jpeg')})
    assert upload.status_code == 201, upload.text
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=seller,
        json={'request_id': 'safety-publish-1', 'title': 'Кукла', 'submit': True,
              'listings': [{'pavilion_id': pavilion, 'price': 500,
                            'sale_modes': ['retail']}]})
    assert saved.status_code == 200, saved.text
    return c, codes, seller, pavilion, pid


def test_report_requires_login_and_published_product_and_deduplicates(env, monkeypatch):
    c, codes, seller, pavilion, pid = publish(env)
    reporter = login(c, codes, 'safety-reporter@example.com')
    endpoint = f'/api/v1/products/{pid}/report'
    assert c.post(endpoint, json={'reason': 'Подмена изображения'}).status_code == 401
    assert c.post(endpoint, headers=reporter, json={'reason': 'x'}).status_code == 422
    assert c.post(endpoint, headers=reporter, json={'reason': '      '}).status_code == 422
    assert c.post('/api/v1/products/unknown/report', headers=reporter,
                  json={'reason': 'Нарушение правил'}).status_code == 404
    first = c.post(endpoint, headers=reporter, json={'reason': 'Подмена изображения'})
    assert first.status_code == 201, first.text
    repeat = c.post(endpoint, headers=reporter, json={'reason': 'Другая причина'})
    assert repeat.status_code == 201
    with env[2]() as db:
        assert db.query(ProductReport).filter_by(product_id=pid).count() == 1
    _, _, _, staff = provision(c, monkeypatch, username='product-reviewer')
    queue = c.get('/api/v1/moderation/queue', headers=staff).json()
    assert len(queue['product_reports']) == 1
    assert queue['product_reports'][0]['product_id'] == pid
    rid = queue['product_reports'][0]['id']
    dismissed = c.post(f'/api/v1/moderation/product-reports/{rid}/resolve',
                       headers=staff, json={'decision': 'dismiss', 'note': 'Ложная тревога'})
    assert dismissed.status_code == 200, dismissed.text
    assert c.get('/api/v1/products/' + pid).status_code == 200
    assert c.get('/api/v1/moderation/queue', headers=staff).json()['product_reports'] == []
    assert c.post(f'/api/v1/moderation/product-reports/{rid}/resolve',
                  headers=staff, json={'decision': 'hide', 'note': 'Нарушение'}).status_code == 409


def test_staff_takedown_blocks_seller_resume_save_duplicate_and_notifies(env, monkeypatch):
    c, codes, seller, pavilion, pid = publish(env)
    _, _, _, staff = provision(c, monkeypatch, username='product-takedown')
    url = f'/api/v1/moderation/products/{pid}/takedown'
    assert c.post(url, headers=seller, json={'reason': 'Нарушение правил'}).status_code == 401
    assert c.post(url, headers=staff, json={'reason': '   '}).status_code == 422
    stopped = c.post(url, headers=staff, json={'reason': 'Запрещённый контент'})
    assert stopped.status_code == 200, stopped.text
    assert c.get('/api/v1/products/' + pid).status_code == 404
    assert pid not in {item['id'] for item in c.get('/api/v1/products').json()['items']}
    assert c.post(url, headers=staff, json={'reason': 'Повторно'}).status_code == 409
    resume = c.post('/api/v1/merchant/products/actions/resume', headers=seller,
                    json={'request_id': 'safety-resume-1', 'product_ids': [pid]})
    assert resume.status_code == 409
    saved = c.put(f'/api/v1/merchant/products/{pid}/save', headers=seller,
        json={'request_id': 'safety-try-save-2', 'title': 'Переименование', 'submit': True,
              'listings': [{'pavilion_id': pavilion, 'price': 500,
                            'sale_modes': ['retail']}]})
    assert saved.status_code == 409, saved.text
    copied = c.post('/api/v1/merchant/products/actions/duplicate', headers=seller,
                    json={'request_id': 'safety-copy-1', 'product_ids': [pid],
                          'source_pavilion_id': pavilion,
                          'destination_pavilion_ids': [pavilion]})
    assert copied.status_code in (404, 409, 422), copied.text
    with env[2]() as db:
        hold = db.get(ProductSafetyHold, pid)
        assert hold and hold.active
        assert db.query(ModerationAction).filter_by(
            kind='products', target_id=pid, decision='takedown').count() == 1
        notice = db.query(SellerNotification).filter_by(
            target_id=pid, event_type='product_safety').one()
        assert notice.note == 'Запрещённый контент'
    notifications = c.get('/api/v1/merchant/notifications', headers=seller).json()
    assert any(item['event_type'] == 'product_safety' for item in notifications['items'])


def test_report_resolution_can_hide_product_atomically(env, monkeypatch):
    c, codes, seller, pavilion, pid = publish(env)
    reporter = login(c, codes, 'another-reporter@example.com')
    _, _, _, staff = provision(c, monkeypatch, username='product-resolution')
    c.post(f'/api/v1/products/{pid}/report', headers=reporter,
           json={'reason': 'Неподходящий контент'})
    rid = c.get('/api/v1/moderation/queue', headers=staff).json()['product_reports'][0]['id']
    no_reason = c.post(f'/api/v1/moderation/product-reports/{rid}/resolve',
        headers=staff, json={'decision': 'hide'})
    assert no_reason.status_code == 422
    processed = c.post(f'/api/v1/moderation/product-reports/{rid}/resolve',
        headers=staff, json={'decision': 'hide', 'note': 'Контент запрещён'})
    assert processed.status_code == 200, processed.text
    assert c.get('/api/v1/products/' + pid).status_code == 404
    assert c.get('/api/v1/moderation/queue', headers=staff).json()['product_reports'] == []


def test_published_legacy_product_can_be_reported_and_hidden(env, monkeypatch):
    from backend.app.models import Product, Offer, Seller, Pavilion
    c, codes, factory, _ = env
    with factory() as db:
        db.add(Pavilion(id='legacy-pav', zone='А', code='1'))
        db.flush()
        db.add(Seller(id='legacy-seller', name='Продавец', pavilion_id='legacy-pav'))
        db.add(Product(id='legacy-product', title='Демо товар',
                       category='Без категории', description='', colors=[],
                       is_demo=True))
        db.flush()
        db.add(Offer(id='legacy-offer', product_id='legacy-product',
                     seller_id='legacy-seller', pavilion_id='legacy-pav',
                     price=150))
        db.commit()
    reporter = login(c, codes, 'legacy-reporter@example.com')
    _, _, _, staff = provision(c, monkeypatch, username='legacy-reviewer')
    assert c.get('/api/v1/products/legacy-product').status_code == 200
    assert c.post('/api/v1/products/legacy-product/report', headers=reporter,
                  json={'reason': 'Проблема с товаром'}).status_code == 201
    stopped = c.post('/api/v1/moderation/products/legacy-product/takedown',
                     headers=staff, json={'reason': 'Контент недопустим'})
    assert stopped.status_code == 200, stopped.text
    assert c.get('/api/v1/products/legacy-product').status_code == 404
    # Legacy administrator cannot bypass a staff hold by toggling visibility.
    admin_client(c)
    assert c.put('/api/v1/admin/products/legacy-product/visibility',
                 json={'active': True}).status_code == 409
