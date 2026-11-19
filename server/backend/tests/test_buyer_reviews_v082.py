from sqlalchemy import select

from backend.app import account as auth
from backend.app.models import Pavilion, Seller
from backend.app.merchant_models import ShopMembership, ShopRecord
from backend.app.buyer_reviews_v082 import BuyerSellerNote, SellerReview, ReviewReport
from backend.tests.test_account import setup, login


def seller(sessions):
    with sessions() as db:
        db.add(Pavilion(id='p01', code='Б-2В-81', zone='Б'))
        db.flush()
        db.add(Seller(id='s01', name='Павильон', pavilion_id='p01'))
        db.commit()


def test_notes_are_private_and_persist_only_for_owner(setup):
    c,codes,sessions=setup
    seller(sessions)
    alice=login(c,codes,'one@example.com');bob=login(c,codes,'two@example.com')
    assert c.get('/api/v1/sellers/s01/my-note').status_code==401
    assert c.post('/api/v1/sellers/s01/my-note',headers=alice,json={'text':' моя заметка '}).json()['text']=='моя заметка'
    assert c.get('/api/v1/sellers/s01/my-note',headers=bob).json()['text']==''
    assert c.get('/api/v1/sellers/s01/my-note',headers=alice).json()['text']=='моя заметка'
    public=c.get('/api/v1/sellers/s01/reviews').json()
    assert 'заметка' not in str(public)


def test_reviews_edit_ratings_and_photo_limit(setup):
    c,codes,sessions=setup
    seller(sessions)
    a=login(c,codes,'first@example.com')
    assert c.post('/api/v1/sellers/s01/reviews',json={'rating':4}).status_code==401
    assert c.post('/api/v1/sellers/s01/reviews',headers=a,json={'rating':6}).status_code==422
    r=c.post('/api/v1/sellers/s01/reviews',headers=a,json={'rating':4,'text':'Хорошо'})
    assert r.status_code==200,r.text
    review_id=r.json()['item']['id']
    r=c.post('/api/v1/sellers/s01/reviews',headers=a,json={'rating':5,'text':'Отлично'})
    assert r.status_code==200 and r.json()['item']['id']==review_id
    r=c.get('/api/v1/sellers/s01/reviews')
    # New and edited reviews remain private until moderator approval.
    assert r.status_code==200 and r.json()['count']==0
    assert c.get('/api/v1/sellers/s01/my-review',headers=a).json()['item']['moderation_status']=='pending'
    with sessions() as db:
        db.get(SellerReview,review_id).moderation_status='approved'
        db.commit()
    r=c.get('/api/v1/sellers/s01/reviews')
    assert r.status_code==200 and r.json()['average']==5.0 and r.json()['count']==1
    assert r.json()['verified_purchases'] is False
    assert c.post('/api/v1/sellers/s01/reviews',headers=a,json={'rating':4,'photos':['invalid-base64']}).status_code==422
    assert c.get('/api/v1/sellers/s01/reviews').json()['items'][0]['rating']==5
    with sessions() as db:
        assert len(db.scalars(select(SellerReview)).all())==1


def test_reports_moderation_and_owner_isolation(setup,monkeypatch):
    c,codes,sessions=setup
    seller(sessions)
    alice=login(c,codes,'one@example.com');bob=login(c,codes,'two@example.com')
    r=c.post('/api/v1/sellers/s01/reviews',headers=alice,json={'rating':2,'text':'Плохо'})
    rid=r.json()['item']['id']
    with sessions() as db:
        db.get(SellerReview,rid).moderation_status='approved'
        db.commit()
    # Even an approved published review must not accept its author's report.
    own_report = c.post(f'/api/v1/sellers/s01/reviews/{rid}/report',
                        headers=alice, json={'reason':'Сам себе жалуюсь'})
    assert own_report.status_code == 403
    assert 'собственный' in own_report.json()['detail']
    with sessions() as db:
        assert db.scalar(select(ReviewReport)) is None
    # A different authenticated buyer can still report the same review.
    assert c.post(f'/api/v1/sellers/s01/reviews/{rid}/report',headers=bob,json={'reason':'Спам и флуд'}).status_code==200
    assert c.post(f'/api/v1/sellers/s01/reviews/{rid}/report',headers=bob,json={'reason':'Повтор'}).status_code==200
    with sessions() as db:
        assert len(db.scalars(select(ReviewReport)).all())==1
    assert c.post(f'/api/v1/merchant/reviews/{rid}/reply',headers=bob,json={'text':'Ответ'}).status_code==403
    monkeypatch.setenv('ADMIN_TOKEN','test-admin-secret')
    admin={'Authorization':'Bearer test-admin-secret'}
    assert c.get('/api/v1/admin/reviews/reports').status_code==401
    assert c.get('/api/v1/admin/reviews/reports',headers=admin).json()['items'][0]['review_id']==rid
    assert c.post(f'/api/v1/admin/reviews/{rid}/moderate',headers=admin,json={'hidden':True}).status_code==200
    assert c.get('/api/v1/sellers/s01/reviews').json()['count']==0
    assert c.post('/api/v1/sellers/s01/reviews',headers=alice,json={'rating':5}).status_code==403
    assert c.post(f'/api/v1/admin/reviews/{rid}/moderate',headers=admin,json={'hidden':False}).status_code==200
    with sessions() as db:
        member=db.scalar(select(auth.Buyer).where(auth.Buyer.email=='two@example.com'))
        db.add(ShopMembership(buyer_id=member.id,seller_id='s01',role='owner'))
        db.add(ShopRecord(seller_id='s01'))
        db.commit()
    assert c.post(f'/api/v1/merchant/reviews/{rid}/reply',headers=bob,json={'text':'Спасибо!'}).status_code==200
    assert c.get('/api/v1/sellers/s01/reviews').json()['items'][0]['reply']=='Спасибо!'


def test_deleting_one_buyer_cleans_private_notes_and_reviews(setup):
    c,codes,sessions=setup
    seller(sessions)
    alice=login(c,codes,'one@example.com');bob=login(c,codes,'two@example.com')
    c.post('/api/v1/sellers/s01/my-note',headers=alice,json={'text':'Личный текст'})
    r=c.post('/api/v1/sellers/s01/reviews',headers=alice,json={'rating':3})
    rid=r.json()['item']['id']
    c.post(f'/api/v1/sellers/s01/reviews/{rid}/report',headers=bob,json={'reason':'некорректный отзыв'})
    assert c.delete('/api/v1/account',headers=alice).status_code==200
    with sessions() as db:
        assert db.scalar(select(BuyerSellerNote)) is None
        assert db.scalar(select(SellerReview)) is None
        assert db.scalar(select(ReviewReport)) is None
        assert db.scalar(select(auth.Buyer).where(auth.Buyer.email=='two@example.com')) is not None
