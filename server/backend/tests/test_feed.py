"""Hybrid feed weights, diversity, pagination, auth isolation and real signals."""
import time
from sqlalchemy import select
from backend.app.account import Buyer
from backend.app.feed import Candidate, affinity, rank, candidates, record_publication
from backend.app.feed_config import WEIGHTS
from backend.app.feed_models import FeedPublication, FeedView
from backend.app.models import Product, ProductDetails, Offer, Pavilion, Seller
from test_merchant_v080 import env, login, admin_client, applicant, approve, make_published


def test_rank_weights_and_diversity():
    assert sum(WEIGHTS.values()) == 1.0 or abs(sum(WEIGHTS.values())-1) < 1e-9
    assert WEIGHTS == dict(interest=.4,popularity=.2,freshness=.15,quality=.1,seller_rating=.1,exploration=.05)
    rows = [Candidate(f'a{i}', 'one-shop', 'clothing-skirts', 1,1,1,1,1,0) for i in range(30)]
    rows += [Candidate(f'b{i}', f'shop-{i}', f'category-{i%5}', 0,.5,.7,.5,.7,.7) for i in range(30)]
    ids = rank(rows,'same-seed')
    assert ids == rank(rows,'same-seed')
    assert len(ids) == len(rows) == len(set(ids))
    assert sum(i.startswith('a') for i in ids[:20]) <= 4
    assert ids[0].startswith('a')
    assert affinity('clothing-skirts', {'clothing-skirts':10}) == 1
    assert affinity('shoes', {'clothing-skirts':10}) == 0


def test_feed_personalizes_without_leaking_and_pages_stably(env):
    c,codes,factory,_ = env
    first = login(c,codes,'feed-first@example.test')
    second = login(c,codes,'feed-second@example.test')
    with factory() as db:
        db.add(Pavilion(id='feed-p', code='А-12',zone='Корпус А'))
        db.flush()
        for i in range(30):
            sid=f'feed-s-{i}'
            pid=f'feed-p-{i:02}'
            db.add(Seller(id=sid,name=sid,pavilion_id='feed-p'))
            db.add(Product(id=pid,title='Юбка' if i<15 else 'Кроссовки',
                category='Одежда' if i<15 else 'Обувь',description='',colors=[],is_demo=False,
                details=ProductDetails(active=True,sizes=[])))
            db.flush()
            db.add(Offer(id=f'feed-o-{i}',product_id=pid,seller_id=sid,pavilion_id='feed-p',price=1000))
        db.commit()
    for auth,query in [(first,'юбки'),(second,'кроссовки')]:
        for _ in range(3):
            r=c.post('/api/v1/account/interests/search',headers=auth,json={'query':query})
            assert r.status_code==200 and r.json()['tracked'], r.text
    url='/api/v1/feed'
    a=c.get(url,headers=first); b=c.get(url,headers=second)
    assert a.status_code==b.status_code==200, (a.text,b.text)
    aa,bb=a.json(),b.json()
    assert len(aa['items'])==len(bb['items'])==20
    assert aa['items'][0]['title']=='Юбка'
    assert bb['items'][0]['title']=='Кроссовки'
    cursor=aa['next_cursor']
    assert cursor
    assert c.get(url,params={'cursor':cursor},headers=second).status_code==410
    assert c.get(url,params={'cursor':cursor}).status_code==410
    remaining=c.get(url,params={'cursor':cursor},headers=first).json()
    assert len(remaining['items'])==10
    ids=[x['id'] for x in aa['items']+remaining['items']]
    assert len(ids)==len(set(ids))==30
    assert remaining==c.get(url,params={'cursor':cursor},headers=first).json()
    with factory() as db:
        db.get(ProductDetails,remaining['items'][0]['id']).active=False
        db.commit()
    filtered=c.get(url,params={'cursor':cursor},headers=first).json()
    assert len(filtered['items'])==9
    assert [x['id'] for x in filtered['items']]==[x['id'] for x in remaining['items'][1:]]
    assert c.get(url).status_code==200


def test_real_publication_and_unique_product_views(env):
    c,codes,factory,_=env
    seller=login(c,codes,'feed-seller@example.test')
    buyer=login(c,codes,'feed-buyer@example.test')
    admin_client(c)
    approve(c,f'applications/{applicant(c,"91",seller)}/decision')
    pavilion=c.get('/api/v1/merchant/pavilions',headers=seller).json()['items'][0]['id']
    pid=make_published(c,seller,pavilion,title='Юбка миди')
    with factory() as db:
        initial=db.get(FeedPublication,pid).published_at
        assert initial>time.time()-120
        record_publication(db,pid)
        db.commit()
        assert db.get(FeedPublication,pid).published_at==initial
    for auth,engaged in [(seller,False),(buyer,False),(buyer,False),(buyer,True),(buyer,False)]:
        r=c.post('/api/v1/account/interests/view',headers=auth,json={'product_id':pid,'engaged':engaged})
        assert r.status_code==200,r.text
    with factory() as db:
        rows=db.scalars(select(FeedView).where(FeedView.product_id==pid)).all()
        assert len(rows)==1 and rows[0].engaged
        buyer_id=db.scalar(select(Buyer.id).where(Buyer.email=='feed-buyer@example.test'))
        assert rows[0].buyer_id==buyer_id
        signals=list(candidates(db,buyer_id,'Все',time.time()))
        assert any(x.id==pid and x.popularity>0 and x.interest>0 and x.freshness>.9 for x in signals)
    assert c.delete('/api/v1/account',headers=buyer).status_code==200
    with factory() as db:
        assert not db.scalars(select(FeedView).where(FeedView.product_id==pid)).all()
