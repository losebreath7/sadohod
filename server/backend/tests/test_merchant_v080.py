"""End-to-end seller onboarding, multi-pavilion moderation and tenant isolation."""
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app import account, admin, merchant, product_screening
from backend.app.account import Buyer
from backend.app.admin_auth import require_admin
from backend.app.database import Base, get_db
from backend.app.main import app
from backend.app.models import Offer, ProductDetails
from backend.app.merchant_models import MerchantListing, ShopApplication, ShopMembership


@pytest.fixture
def env(monkeypatch, tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with engine.connect() as connection:
        connection.exec_driver_sql("PRAGMA foreign_keys=ON")
    factory = sessionmaker(engine, expire_on_commit=False)

    def session_override():
        with factory() as db:
            yield db

    app.dependency_overrides[get_db] = session_override
    monkeypatch.setenv('SMTP_HOST', 'smtp.example.test')
    monkeypatch.setenv('SMTP_FROM', 'test@example.test')
    codes = {}
    monkeypatch.setattr(account, 'send_code', lambda email, code: codes.update({email: code}))
    monkeypatch.setattr(admin, 'MEDIA', tmp_path)
    monkeypatch.setattr(admin, 'SEARCH_BACKEND', 'classic')
    # Legacy catalog tests exercise shop/pavilion/catalog workflows, not
    # recognition quality. Simulate a successful photo review for benign
    # content; dedicated moderation tests restore real fail-closed assess().
    original_assess = product_screening.assess
    def approved_test_photo(db, product):
        if product_screening.SEARCH_BACKEND == 'classic':
            return product_screening._text_reason(
                product.title or '', product.description or '')
        return original_assess(db, product)
    monkeypatch.setattr(product_screening, 'assess', approved_test_photo)
    try:
        yield TestClient(app), codes, factory, tmp_path
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


def login(c, codes, email):
    assert c.post('/api/v1/auth/code', json={'email': email}).status_code == 200
    response = c.post('/api/v1/auth/verify', json={'email': email, 'code': codes[email]})
    assert response.status_code == 200, response.text
    return {'Authorization': 'Bearer ' + response.json()['token']}


def admin_client(c):
    app.dependency_overrides[require_admin] = lambda: None
    return c


def applicant(c, code, auth, shop='Точка'):
    response = c.post('/api/v1/merchant/applications', headers=auth,
                      json={'shop_name': shop, 'zone': 'Линия А', 'code': code, 'contact': '@contact'})
    assert response.status_code == 201, response.text
    return response.json()['id']


def approve(c, path, *, decision='approved'):
    result = c.post('/api/v1/admin/merchant/' + path, json={'decision': decision, 'note': ''})
    assert result.status_code == 200, result.text
    return result.json()


def photo():
    buffer = BytesIO(); Image.new('RGB', (80, 80), 'pink').save(buffer, 'JPEG')
    return buffer.getvalue()


def make_published(c, auth, pavilion_id, title='Куртка'):
    p = c.post('/api/v1/merchant/products', headers=auth,
               json={'title': title, 'category': 'Одежда', 'colors': ['розовый'], 'sizes': ['M']})
    assert p.status_code == 201, p.text
    pid = p.json()['id']
    assert c.get('/api/v1/products/'+pid).status_code == 404
    result = c.post(f'/api/v1/merchant/products/{pid}/images', headers=auth,
                    files={'files': ('pink.jpg', photo(), 'image/jpeg')})
    assert result.status_code == 201, result.text
    listing = c.post(f'/api/v1/merchant/products/{pid}/listings', headers=auth,
                     json={'pavilion_id': pavilion_id, 'price': 2500, 'sale_modes': ['wholesale', 'retail']})
    assert listing.status_code == 201, listing.text
    result = c.post(f'/api/v1/merchant/products/{pid}/submit', headers=auth)
    assert result.status_code == 200, result.text
    assert result.json()['status'] == 'approved'
    assert c.get('/api/v1/products/'+pid).status_code == 200
    return pid


def test_complete_flow_isolated_and_public_only_after_approval(env):
    c, codes, factory, files = env
    a = login(c, codes, 'owner@test.com')
    b = login(c, codes, 'stranger@test.com')
    assert c.get('/api/v1/merchant/me').status_code == 401
    assert c.post('/api/v1/merchant/products', headers=a,
                  json={'title': 'Запрещено', 'category': 'Куртки'}).status_code == 403
    aid = applicant(c, '10', a)
    assert c.post('/api/v1/merchant/applications',headers=a,
                  json={'shop_name':'Дубль','zone':'Линия А','code':'11'}).status_code == 409
    assert c.get('/api/v1/admin/merchant/queue').status_code == 401
    admin_client(c)
    approved = approve(c, f'applications/{aid}/decision')
    assert approved['seller_id']
    pavilion_id = c.get('/api/v1/merchant/pavilions', headers=a).json()['items'][0]['id']
    pid = make_published(c, a, pavilion_id)
    assert c.get('/api/v1/products/'+pid).json()['sale_modes'] == ['wholesale', 'retail']
    assert c.get('/api/v1/merchant/products/'+pid, headers=b).status_code == 403
    assert c.get('/api/v1/merchant/products/'+pid).status_code == 401
    # Owned buyer cannot request a second shop; existing users and demo data untouched.
    assert c.post('/api/v1/merchant/applications',headers=a,
                  json={'shop_name':'Магазин','zone':'Линия Б','code':'1'}).status_code == 409
    with factory() as db:
        assert db.query(Offer).filter_by(product_id=pid).count() == 1
        assert db.query(ShopMembership).count() == 1


def test_second_pavilion_requires_moderation_and_ownership(env):
    c, codes, factory, _ = env
    a = login(c, codes, 'first@test.com')
    b = login(c, codes, 'second@test.com')
    admin_client(c)
    approve(c, f'applications/{applicant(c,"3",a)}/decision')
    approve(c, f'applications/{applicant(c,"4",b, "Другой")}/decision')
    first_id = c.get('/api/v1/merchant/pavilions', headers=a).json()['items'][0]['id']
    second_id = c.get('/api/v1/merchant/pavilions', headers=b).json()['items'][0]['id']
    pid = make_published(c, a, first_id)
    assert c.post(f'/api/v1/merchant/products/{pid}/listings',headers=b,
                  json={'pavilion_id':second_id,'price':500,'sale_modes':['retail']}).status_code == 404
    assert c.post(f'/api/v1/merchant/products/{pid}/listings',headers=a,
                  json={'pavilion_id':second_id,'price':500,'sale_modes':['retail']}).status_code == 403
    r = c.post('/api/v1/merchant/pavilions',headers=a,json={'zone':'Линия Б','code':'15'})
    assert r.status_code == 201
    assert len(c.get('/api/v1/merchant/pavilions',headers=a).json()['items']) == 1
    approve(c,'pavilions/'+r.json()['id']+'/decision')
    items = c.get('/api/v1/merchant/pavilions',headers=a).json()['items']
    assert len(items) == 2
    added = c.post(f'/api/v1/merchant/products/{pid}/listings',headers=a,
                   json={'pavilion_id':items[1]['id'],'price':2900,'sale_modes':['retail']})
    assert added.status_code == 201 and added.json()['status']=='approved'
    offers = c.get('/api/v1/products/'+pid).json()['offers']
    assert len(offers) == 2
    assert {o['price'] for o in offers} == {2500,2900}
    assert c.get('/api/v1/merchant/pavilions',headers=b).json()['items'][0]['id'] == second_id


def test_rejected_application_duplicate_pavilion_and_auto_published_product(env):
    c,codes,factory,_ = env
    auth = login(c,codes,'seller@test.com')
    admin_client(c)
    first = applicant(c,'24',auth)
    approve(c,'applications/'+first+'/decision',decision='rejected')
    second = applicant(c,'25',auth)
    approved = approve(c,'applications/'+second+'/decision')
    assert approved['seller_id']
    other=login(c,codes,'other@test.com')
    # Cannot claim an already-approved physical location under a different account.
    assert c.post('/api/v1/merchant/applications',headers=other,
                  json={'shop_name':'Второй','zone':'линия  а','code':'25'}).status_code==409
    pavilion_id = c.get('/api/v1/merchant/pavilions',headers=auth).json()['items'][0]['id']
    p = c.post('/api/v1/merchant/products', headers=auth,json={'title':'Новые джинсы','category':'Одежда'})
    pid = p.json()['id']
    assert c.post(f'/api/v1/merchant/products/{pid}/submit',headers=auth).status_code == 409
    c.post(f'/api/v1/merchant/products/{pid}/images',headers=auth,files={'files':('x.jpg',photo(),'image/jpeg')})
    c.post(f'/api/v1/merchant/products/{pid}/listings',headers=auth,
           json={'pavilion_id':pavilion_id,'price':400,'sale_modes':['wholesale']})
    published = c.post(f'/api/v1/merchant/products/{pid}/submit',headers=auth)
    assert published.status_code == 200 and published.json()['status'] == 'approved'
    assert c.get('/api/v1/products/'+pid).status_code == 200
    assert c.post('/api/v1/admin/merchant/products/'+pid+'/decision',
                  json={'decision':'rejected'}).status_code == 409



def test_approved_product_edit_stays_published_without_moderation(env):
    c,codes,factory,_ = env
    auth=login(c,codes,'editor@test.com');admin_client(c)
    approve(c,'applications/'+applicant(c,'87',auth)+'/decision')
    pavilion=c.get('/api/v1/merchant/pavilions',headers=auth).json()['items'][0]['id']
    pid=make_published(c,auth,pavilion)
    edit=c.put('/api/v1/merchant/products/'+pid,headers=auth,
               json={'title':'Куртка новая','category':'Одежда','sizes':['L']})
    assert edit.status_code==200,edit.text
    assert edit.json()['status'] == 'approved'
    assert c.get('/api/v1/products/'+pid).json()['title']=='Куртка новая'


def test_no_self_approval_or_private_moderation(env):
    c,codes,factory,_=env
    auth=login(c,codes,'unverified@test.com')
    aid=applicant(c,'44',auth)
    assert c.post('/api/v1/admin/merchant/applications/'+aid+'/decision',headers=auth,
                  json={'decision':'approved'}).status_code==401
    assert c.get('/api/v1/admin/merchant/queue',headers=auth).status_code==401
    assert c.get('/api/v1/merchant/products',headers=auth).status_code==403


def test_admin_invitation_is_single_use_email_scoped(env):
    c, codes, _, _ = env
    owner=login(c,codes,'invited@test.com')
    stranger=login(c,codes,'else@test.com')
    admin_client(c)
    response=c.post('/api/v1/admin/merchant/invitations',json={
        'email':'invited@test.com','shop_name':'Приглашённый','contact':'@hello',
        'zone':'Переход 3','code':'52'})
    assert response.status_code==201,response.text
    token=response.json()['invite_token']
    assert token not in c.get('/api/v1/admin/merchant/queue').text
    assert c.post('/api/v1/merchant/invitations/accept',headers=stranger,json={'token':token}).status_code==403
    accepted=c.post('/api/v1/merchant/invitations/accept',headers=owner,json={'token':token})
    assert accepted.status_code==201,accepted.text
    assert accepted.json()['name']=='Приглашённый'
    assert c.post('/api/v1/merchant/invitations/accept',headers=owner,json={'token':token}).status_code==400
    assert c.get('/api/v1/merchant/pavilions',headers=owner).status_code==200


def test_price_update_pause_resume_immediate(env):
    c,codes,_,_=env
    owner=login(c,codes,'owner2@test.com')
    admin_client(c)
    approve(c,'applications/'+applicant(c,'99',owner)+'/decision')
    pavilion=c.get('/api/v1/merchant/pavilions',headers=owner).json()['items'][0]['id']
    pid=make_published(c,owner,pavilion)
    listing=c.get('/api/v1/merchant/products/'+pid,headers=owner).json()['listings'][0]
    lid=listing['id']
    change=c.put('/api/v1/merchant/listings/'+lid,headers=owner,json={
        'pavilion_id':pavilion,'price':3100,'sale_modes':['retail']})
    assert change.status_code==200 and change.json()['status']=='approved'
    assert c.get('/api/v1/products/'+pid).json()['price']==3100
    pause=c.post('/api/v1/merchant/listings/'+lid+'/pause',headers=owner)
    assert pause.status_code==200, pause.text
    assert c.get('/api/v1/products/'+pid).status_code==404
    assert c.post('/api/v1/merchant/listings/'+lid+'/resume',headers=owner).status_code==200
    assert c.get('/api/v1/products/'+pid).status_code==200


def test_pages_and_public_pavilion_for_each_offer(env):
    c,codes,_,_=env
    assert c.get('/preview/merchant.html').status_code==200
    assert 'КАБИНЕТ ПРОДАВЦА' in c.get('/preview/merchant.html').text
    assert c.get('/preview/merchant.js').status_code==200
    assert c.get('/preview/merchant_admin.html').status_code==200
    auth=login(c,codes,'buyer6@test.com');admin_client(c)
    approved=approve(c,'applications/'+applicant(c,'14',auth)+'/decision')
    seller_id=approved['seller_id']
    pavilion=c.get('/api/v1/merchant/pavilions',headers=auth).json()['items'][0]['id']
    pid=make_published(c,auth,pavilion)
    detail=c.get('/api/v1/products/'+pid).json()
    assert detail['offers'][0]['pavilion']['id']==pavilion
    assert c.get('/api/v1/pavilions/'+pavilion).json()['code']=='14'
    assert c.get('/api/v1/sellers/'+seller_id).json()['pavilions'][0]['id']==pavilion


def test_merchant_role_cannot_use_admin_token(env):
    c,codes,_,_=env
    owner=login(c,codes,'noadmin@test.com')
    assert c.get('/api/v1/admin/merchant/queue',headers=owner).status_code==401
    assert c.post('/api/v1/admin/merchant/invitations',headers=owner,json={
      'email':'noadmin@test.com','shop_name':'Тест', 'zone':'Линия','code':'5'}).status_code==401


def test_close_seller_account_preserves_buyer_and_releases_all_pavilions(env):
    c, codes, _, _ = env
    owner = login(c, codes, 'owner@example.test')
    other = login(c, codes, 'other@example.test')
    admin_client(c)
    sid = approve(c, f'applications/{applicant(c,"10",owner)}/decision')['seller_id']
    other_sid = approve(c, f'applications/{applicant(c,"20",other)}/decision')['seller_id']
    req = c.post('/api/v1/merchant/pavilions', headers=owner, json={'zone':'Б','code':'11'})
    approve(c, f'pavilions/{req.json()["id"]}/decision')
    pavilions = c.get('/api/v1/merchant/pavilions', headers=owner).json()['items']
    products = [make_published(c, owner, p['id']) for p in pavilions]
    assert len(products) == 2
    assert c.post('/api/v1/account/favorite', headers=owner, json={
        'kind':'seller', 'id':other_sid, 'saved':True}).is_success
    before = c.get('/api/v1/account', headers=owner).json()
    review = c.post(f'/api/v1/sellers/{sid}/reviews', headers=other,
                    json={'rating':5,'text':'Отзыв'})
    assert review.is_success, review.text
    for _ in range(2):
        response = c.delete('/api/v1/merchant/account', headers=owner)
        assert response.is_success, response.text
    for path in [f'sellers/{sid}', f'sellers/{sid}/reviews', *[f'products/{p}' for p in products]]:
        assert c.get('/api/v1/'+path).status_code == 404
    assert c.get('/api/v1/account', headers=owner).json() == before
    assert c.get('/api/v1/merchant/me', headers=owner).json()['shop'] is None
    assert c.get('/api/v1/merchant/shop', headers=other).json()['id'] == other_sid
    for zone, code in [('Линия А','10'),('Б','11')]:
        assert c.post('/api/v1/merchant/pavilions', headers=other,
                      json={'zone':zone,'code':code}).is_success
    assert c.get('/api/v1/account', headers=login(c,codes,'owner@example.test')).json() == before
