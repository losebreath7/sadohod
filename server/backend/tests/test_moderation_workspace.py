"""Security and workflow tests for the separate moderation workspace."""
import time
from sqlalchemy import select

from backend.app.account import Buyer
from backend.app.buyer_reviews_v082 import SellerReview
from backend.app.moderation_models import ModeratorSession, ModerationAction
from backend.app.models import Pavilion, Seller
from backend.tests.test_account import setup, login


def provision(client, monkeypatch, username='staff-a'):
    monkeypatch.setenv('ADMIN_TOKEN', 'integration-admin-key')
    admin = {'Authorization': 'Bearer integration-admin-key'}
    created = client.post('/api/v1/admin/moderators', headers=admin,
        json={'username': username, 'display_name': 'Мария Модератор'})
    assert created.status_code == 201, created.text
    secret = created.json()['one_time_password']
    assert len(secret) >= 24
    auth = client.post('/api/v1/moderation/login',
        json={'username':username, 'password':secret})
    assert auth.status_code == 200, auth.text
    token = auth.json()['token']
    return admin, created.json()['user'], secret, {'Authorization':'Bearer '+token}


def test_staff_auth_isolation_revocation_and_secret_rotation(setup, monkeypatch):
    c, codes, sessions = setup
    buyer = login(c, codes, 'not-a-moderator@example.com')
    assert c.get('/api/v1/moderation/queue').status_code == 401
    assert c.get('/api/v1/moderation/queue', headers=buyer).status_code == 401
    assert c.post('/api/v1/admin/moderators',
        json={'username':'bad', 'display_name':'Bad'}).status_code == 401
    admin, staff, password, headers = provision(c, monkeypatch)
    assert c.get('/api/v1/moderation/me', headers=headers).json()['user']['username']=='staff-a'
    assert c.get('/api/v1/moderation/queue', headers=headers).status_code == 200
    assert c.get('/api/v1/admin/moderators', headers=headers).status_code == 401
    listing = c.get('/api/v1/admin/moderators', headers=admin).json()['items']
    assert listing[0]['id']==staff['id'] and password not in str(listing)
    assert c.post('/api/v1/moderation/login',
        json={'username':'staff-a','password':'incorrect'}).status_code == 401
    with sessions() as db:
        saved = db.scalar(select(ModeratorSession))
        assert saved is not None and len(saved.digest) == 64 and saved.digest != headers['Authorization'].split()[1]
    changed=c.post('/api/v1/admin/moderators/'+staff['id']+'/reset-password',headers=admin)
    assert changed.status_code==200
    assert c.get('/api/v1/moderation/me',headers=headers).status_code==401
    new = changed.json()['one_time_password']
    new_login = c.post('/api/v1/moderation/login',json={'username':'staff-a','password':new})
    assert new_login.status_code==200
    updated = {'Authorization':'Bearer '+new_login.json()['token']}
    assert c.put('/api/v1/admin/moderators/'+staff['id'],headers=admin,json={'enabled':False}).status_code==200
    assert c.get('/api/v1/moderation/queue',headers=updated).status_code==401


def test_moderator_approves_pavilion_application_and_writes_audit(setup, monkeypatch):
    c, codes, sessions = setup
    buyer = login(c, codes, 'seller@example.com')
    admin, staff, _, headers = provision(c, monkeypatch)
    submitted=c.post('/api/v1/merchant/applications',headers=buyer,json={
        'shop_name':'Точка А', 'zone':'Б-2В', 'code':'81', 'contact':'@seller'})
    assert submitted.status_code==201,submitted.text
    aid = submitted.json()['id']
    queue = c.get('/api/v1/moderation/queue',headers=headers).json()
    assert any(x['id']==aid for x in queue['applications'])
    assert c.post('/api/v1/moderation/applications/'+aid+'/decision',
        headers=buyer,json={'decision':'approved'}).status_code==401
    result = c.post('/api/v1/moderation/applications/'+aid+'/decision',
        headers=headers,json={'decision':'approved'})
    assert result.status_code==200,result.text
    assert result.json()['status']=='approved'
    repeat=c.post('/api/v1/moderation/applications/'+aid+'/decision',
        headers=headers,json={'decision':'approved'})
    assert repeat.status_code==409
    actions=c.get('/api/v1/moderation/history',headers=headers).json()['items']
    assert len(actions)==1 and actions[0]['moderator']=='Мария Модератор'
    assert actions[0]['target_id']==aid and actions[0]['decision']=='approved'
    assert c.get('/api/v1/merchant/pavilions',headers=buyer).json()['items']
    assert c.get('/api/v1/admin/merchant/queue',headers=headers).status_code==401


def test_review_premoderation_reports_and_private_visibility(setup, monkeypatch):
    c,codes,sessions=setup
    with sessions() as db:
        db.add(Pavilion(id='r-pav', code='19', zone='А'))
        db.flush()
        db.add(Seller(id='r-seller', name='Продавец', pavilion_id='r-pav'))
        db.commit()
    buyer=login(c,codes,'author@example.com')
    reporter=login(c,codes,'reporter@example.com')
    _,_,_,staff=provision(c,monkeypatch)
    new=c.post('/api/v1/sellers/r-seller/reviews',headers=buyer,
        json={'rating':4,'text':'Проверенный отзыв'})
    assert new.status_code==200,new.text
    rid=new.json()['item']['id']
    assert new.json()['item']['moderation_status']=='pending'
    assert c.get('/api/v1/sellers/r-seller/reviews').json()['count']==0
    assert c.post('/api/v1/sellers/r-seller/reviews/'+rid+'/report',headers=reporter,
        json={'reason':'Неправильный отзыв'}).status_code==404
    q=c.get('/api/v1/moderation/queue',headers=staff).json()
    assert len(q['reviews'])==1 and q['reviews'][0]['id']==rid
    assert c.post('/api/v1/moderation/reviews/'+rid+'/decision',headers=staff,
        json={'decision':'rejected','note':''}).status_code==422
    ok=c.post('/api/v1/moderation/reviews/'+rid+'/decision',headers=staff,
        json={'decision':'approved'})
    assert ok.status_code==200,ok.text
    assert c.get('/api/v1/sellers/r-seller/reviews').json()['count']==1
    assert c.post('/api/v1/sellers/r-seller/reviews/'+rid+'/report',
        headers=reporter,json={'reason':'Неправильный отзыв'}).status_code==200
    q=c.get('/api/v1/moderation/queue',headers=staff).json()
    assert len(q['reports'])==1
    reportid=q['reports'][0]['id']
    hidden=c.post('/api/v1/moderation/reports/'+reportid+'/resolve',headers=staff,
        json={'decision':'hide','note':'Нарушение правил'})
    assert hidden.status_code==200
    assert c.get('/api/v1/sellers/r-seller/reviews').json()['count']==0
    assert c.post('/api/v1/moderation/reports/'+reportid+'/resolve',headers=staff,
        json={'decision':'dismiss'}).status_code==409
    assert c.get('/api/v1/moderation/queue',headers=staff).json()['reports']==[]


def test_rejected_review_can_be_edited_and_resubmitted(setup,monkeypatch):
    c,codes,sessions=setup
    with sessions() as db:
        db.add(Pavilion(id='edit-pav', code='10', zone='Г'));db.flush()
        db.add(Seller(id='edit-seller', name='Продавец', pavilion_id='edit-pav'));db.commit()
    buyer=login(c,codes,'edit@example.com')
    _,_,_,staff=provision(c,monkeypatch)
    first=c.post('/api/v1/sellers/edit-seller/reviews',headers=buyer,
        json={'rating':1,'text':'Первый'})
    rid=first.json()['item']['id']
    assert c.post('/api/v1/moderation/reviews/'+rid+'/decision',headers=staff,
        json={'decision':'rejected','note':'Не по теме'}).status_code==200
    assert c.get('/api/v1/sellers/edit-seller/reviews').json()['count']==0
    second=c.post('/api/v1/sellers/edit-seller/reviews',headers=buyer,
        json={'rating':3,'text':'Исправленный отзыв'})
    assert second.status_code==200
    assert second.json()['item']['moderation_status']=='pending'
    assert second.json()['item']['id']==rid
    assert c.get('/api/v1/moderation/queue',headers=staff).json()['reviews'][0]['text']=='Исправленный отзыв'


def test_moderation_pages_are_available_without_exposing_private_api(setup):
    c,_,_=setup
    for path in ('moderation.html','moderation.js','moderation.css',
                 'moderation-team.html','moderation-team.js'):
        r=c.get('/preview/'+path)
        assert r.status_code==200,path
        assert 'text/html' in r.headers.get('content-type','') if path.endswith('.html') else bool(r.content)
    assert c.get('/api/v1/moderation/history').status_code==401
    assert c.get('/api/v1/moderation/chats').status_code==401
