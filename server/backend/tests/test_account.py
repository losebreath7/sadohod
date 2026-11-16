import time
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from backend.app.database import Base, get_db
from backend.app.main import app
from backend.app import account as auth

@pytest.fixture
def setup(monkeypatch):
    engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
    Base.metadata.create_all(engine)
    sessions=sessionmaker(engine,expire_on_commit=False)
    def db():
        with sessions() as s: yield s
    app.dependency_overrides[get_db]=db
    monkeypatch.setenv('SMTP_HOST','test.invalid')
    monkeypatch.setenv('SMTP_FROM','app@test.invalid')
    codes={}
    monkeypatch.setattr(auth,'send_code',lambda email,code:codes.update({email:code}))
    yield TestClient(app),codes,sessions
    app.dependency_overrides.clear()
    engine.dispose()

def login(c,codes,email):
    assert c.post('/api/v1/auth/code',json={'email':email}).status_code==200
    r=c.post('/api/v1/auth/verify',json={'email':email,'code':codes[email]})
    assert r.status_code==200,r.text
    return {'Authorization':'Bearer '+r.json()['token']}

def test_login_favorites_isolation_and_deletion(setup):
    c,codes,sessions=setup
    a=login(c,codes,'a@example.com'); b=login(c,codes,'b@example.com')
    assert c.get('/api/v1/account').status_code==401
    for _ in range(2):
        assert c.post('/api/v1/account/merge',headers=a,json={'products':['p01','p01'],'sellers':['s01']}).status_code==200
    assert c.get('/api/v1/account',headers=a).json()['products']==['p01']
    assert c.get('/api/v1/account',headers=b).json()['products']==[]
    c.post('/api/v1/account/profile',headers=a,json={'name':'  Жанель  '})
    assert c.get('/api/v1/account',headers=a).json()['name']=='Жанель'
    c.post('/api/v1/account/favorite',headers=a,json={'kind':'product','id':'p01','saved':False})
    assert c.get('/api/v1/account',headers=a).json()['products']==[]
    assert c.delete('/api/v1/account',headers=a).status_code==200
    assert c.get('/api/v1/account',headers=a).status_code==401
    assert c.get('/api/v1/account',headers=b).status_code==200
    with sessions() as db:
        assert db.scalar(select(auth.Buyer).where(auth.Buyer.email=='a@example.com')) is None
        assert len(db.scalars(select(auth.Favorite)).all())==0

def test_otp_replay_wrong_attempts_expiry(setup):
    c,codes,sessions=setup
    a=login(c,codes,'a@example.com')
    assert c.post('/api/v1/auth/verify',json={'email':'a@example.com','code':codes['a@example.com']}).status_code==400
    c.post('/api/v1/auth/code',json={'email':'c@example.com'})
    wrong='000001' if codes['c@example.com']=='000000' else '000000'
    for _ in range(5): assert c.post('/api/v1/auth/verify',json={'email':'c@example.com','code':wrong}).status_code==400
    assert c.post('/api/v1/auth/verify',json={'email':'c@example.com','code':codes['c@example.com']}).status_code==400
    c.post('/api/v1/auth/code',json={'email':'d@example.com'})
    with sessions() as db:
        db.get(auth.LoginCode,'d@example.com').expires=time.time()-1; db.commit()
    assert c.post('/api/v1/auth/verify',json={'email':'d@example.com','code':codes['d@example.com']}).status_code==400
    assert c.post('/api/v1/auth/logout',headers=a).status_code==200
    assert c.get('/api/v1/account',headers=a).status_code==401

def test_resend_and_smtp_failure(setup,monkeypatch):
    c,codes,sessions=setup
    r=c.post('/api/v1/auth/code',json={'email':'A@example.com'})
    assert r.status_code==200 and 'code' not in r.json()
    assert c.post('/api/v1/auth/code',json={'email':'a@example.com'}).status_code==429
    def fail(*args):raise RuntimeError('private smtp diagnostic')
    monkeypatch.setattr(auth,'send_code',fail)
    r=c.post('/api/v1/auth/code',json={'email':'b@example.com'})
    assert r.status_code==503 and 'private' not in r.text
    with sessions() as db: assert db.get(auth.LoginCode,'b@example.com') is None
    monkeypatch.delenv('SMTP_HOST')
    assert c.post('/api/v1/auth/code',json={'email':'d@example.com'}).status_code==503
    assert c.post('/api/v1/auth/code',json={'email':'a\nb@example.com'}).status_code==422

def test_resend_invalidates_previous_and_session_expires(setup):
    c,codes,sessions=setup
    c.post('/api/v1/auth/code',json={'email':'a@example.com'})
    with sessions() as db:
        row=db.get(auth.LoginCode,'a@example.com');row.sent=time.time()-61;previous=row.digest;db.commit()
    c.post('/api/v1/auth/code',json={'email':'a@example.com'})
    with sessions() as db: assert db.get(auth.LoginCode,'a@example.com').digest!=previous
    r=c.post('/api/v1/auth/verify',json={'email':'a@example.com','code':codes['a@example.com']})
    h={'Authorization':'Bearer '+r.json()['token']}
    with sessions() as db:
        db.scalar(select(auth.BuyerSession)).expires=time.time()-1;db.commit()
    assert c.get('/api/v1/account',headers=h).status_code==401
