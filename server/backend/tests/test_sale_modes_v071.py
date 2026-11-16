from backend.tests.test_api import client
from backend.tests.test_admin import editor, seller, upload


def test_demo_sale_modes_are_explicit(client):
    product = client.get('/api/v1/products/p03').json()
    assert product['sale_modes'] == ['wholesale', 'retail']
    assert product['offers'][0]['sale_modes'] == ['wholesale', 'retail']
    # The imported photo dataset is not given invented sale modes.


def test_admin_must_choose_sale_mode_before_publishing(editor):
    shop = seller(editor)
    base = dict(title='Свитер', category='Одежда', price=1200,
                seller_id=shop['id'], colors=[], sizes=[])
    product = editor.post('/api/v1/admin/products', json=base)
    assert product.status_code == 201
    pid = product.json()['id']
    assert product.json()['sale_modes'] == []
    assert upload(editor, pid).status_code == 201
    forbidden = editor.put(f'/api/v1/admin/products/{pid}/visibility', json={'active': True})
    assert forbidden.status_code == 409
    assert 'способ продажи' in forbidden.text
    edited = editor.put(f'/api/v1/admin/products/{pid}', json={**base, 'sale_modes':['retail']})
    assert edited.status_code == 200
    assert edited.json()['sale_modes'] == ['retail']
    assert editor.put(f'/api/v1/admin/products/{pid}/visibility', json={'active': True}).status_code == 200
    fetched = editor.get(f'/api/v1/products/{pid}').json()
    assert fetched['sale_modes'] == ['retail']
    both = editor.put(f'/api/v1/admin/products/{pid}',json={**base, 'sale_modes':['wholesale','retail']})
    assert both.status_code == 200
    assert both.json()['sale_modes'] == ['wholesale', 'retail']
    assert editor.put(f'/api/v1/admin/products/{pid}',json={**base, 'sale_modes':[]}).status_code == 422


def test_demo_backfill_does_not_override_seller_setting(client):
    from backend.app.seed import ensure_legacy_demo_sale_modes
    from backend.app.models import Offer, OfferSaleModes
    from backend.app.database import get_db
    from backend.app.main import app
    with next(app.dependency_overrides[get_db]()) as db:
        offer = db.get(Offer, 'o-p03')
        offer.modes = OfferSaleModes(wholesale=False, retail=True)
        db.commit()
        ensure_legacy_demo_sale_modes(db)
        db.expire_all()
        assert db.get(Offer,'o-p03').modes.retail is True
        assert db.get(Offer,'o-p03').modes.wholesale is False
