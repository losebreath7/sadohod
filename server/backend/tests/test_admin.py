from pathlib import Path
from unittest.mock import Mock
import pytest
from sqlalchemy import select, func
from backend.tests.test_api import client
from backend.app import admin
from backend.app.main import app
from backend.app.admin_auth import require_admin
from backend.app.config import MEDIA
from backend.app.database import get_db
from backend.app.models import ProductImage, ImageMLEmbedding


@pytest.fixture
def editor(client, monkeypatch, tmp_path):
    app.dependency_overrides[require_admin]=lambda: None
    monkeypatch.setattr(admin,'MEDIA',tmp_path)
    monkeypatch.setattr(admin,'SEARCH_BACKEND','classic')
    yield client
    app.dependency_overrides.pop(require_admin,None)


def seller(c):
    r=c.post('/api/v1/admin/sellers',json={'name':'Тестовый магазин','contact':'@test','zone':'Сектор А · ряд 2','pavilion':'18'})
    assert r.status_code==201,r.text
    return r.json()


def draft(c):
    s=seller(c)
    payload={'title':'Моя куртка','category':'Тестовая категория','description':'Описание','price':2500,'seller_id':s['id'],'sizes':['S','M'],'colors':['Розовый'],'sale_modes':['wholesale','retail']}
    r=c.post('/api/v1/admin/products',json=payload)
    assert r.status_code==201,r.text
    return r.json(),payload


def upload(c,pid,raw=None):
    return c.post(f'/api/v1/admin/products/{pid}/images',files={'files':('photo.jpg',raw or (MEDIA/'p01.jpg').read_bytes(),'image/jpeg')})


def test_auth_rejects_missing_or_wrong_token(client,monkeypatch):
    monkeypatch.setenv('ADMIN_TOKEN','test-only-token')
    assert client.get('/api/v1/admin/products').status_code==401
    assert client.get('/api/v1/admin/products',headers={'Authorization':'Bearer bad'}).status_code==401
    assert client.get('/api/v1/admin/status',headers={'Authorization':'Bearer test-only-token'}).status_code==200


def test_add_publish_find_edit_hide_restore(editor):
    c=editor;p,payload=draft(c);pid=p['id']
    assert not p['active'] and not p['demo']
    assert c.get('/api/v1/products/'+pid).status_code==404
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',json={'active':True}).status_code==409
    r=upload(c,pid);assert r.status_code==201,r.text
    p=r.json();assert len(p['images'])==1
    raw=(admin.MEDIA/p['images'][0].removeprefix('/media/products/')).read_bytes()
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',json={'active':True}).status_code==200
    public=c.get('/api/v1/products/'+pid).json()
    assert public['sizes']==['S','M'] and public['offers'][0]['seller']['contact']=='@test'
    search=lambda: c.post('/api/v1/search/image?category=Тестовая категория',files={'file':('q.jpg',raw,'image/jpeg')}).json()['items']
    assert search()[0]['product']['id']==pid
    payload.update(title='Новое название',price=3000,sizes=['L'])
    assert c.put('/api/v1/admin/products/'+pid,json=payload).status_code==200
    assert c.get('/api/v1/products/'+pid).json()['price']==3000
    assert c.delete(f"/api/v1/admin/products/{pid}/images/{p['image_records'][0]['id']}").status_code==409
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',json={'active':False}).status_code==200
    assert not search()
    assert c.get('/api/v1/products/'+pid).status_code==404
    assert not c.get('/api/v1/sellers/'+payload['seller_id']).json()['products']
    assert 'Тестовая категория' not in c.get('/api/v1/categories').json()['items']
    assert c.put(f'/api/v1/admin/products/{pid}/visibility',json={'active':True}).status_code==200
    assert search()[0]['product']['id']==pid


def test_failed_batch_upload_is_atomic(editor,monkeypatch):
    p,_=draft(editor);pid=p['id']
    monkeypatch.setattr(admin,'SEARCH_BACKEND','clip')
    monkeypatch.setattr(admin,'embed_image',Mock(side_effect=[[1.0]+[0.0]*511,RuntimeError('offline')]))
    raw=(MEDIA/'p01.jpg').read_bytes()
    r=editor.post(f'/api/v1/admin/products/{pid}/images',files=[('files',('a.jpg',raw,'image/jpeg')),('files',('b.jpg',raw,'image/jpeg'))])
    assert r.status_code==503
    result=next(p for p in editor.get('/api/v1/admin/products').json()['items'] if p['id']==pid)
    assert result['images']==[]
    assert not list(admin.MEDIA.rglob('*.jpg'))


def test_clip_upload_indexes_then_removes(editor,monkeypatch):
    monkeypatch.setattr(admin,'SEARCH_BACKEND','clip')
    monkeypatch.setattr(admin,'embed_image',lambda data:[1.0]+[0.0]*511)
    p,_=draft(editor);r=upload(editor,p['id']);assert r.status_code==201
    iid=r.json()['image_records'][0]['id']
    with next(app.dependency_overrides[get_db]()) as db:
        assert db.get(ImageMLEmbedding,(iid,admin.MODEL_ID)) is not None
    assert editor.delete(f"/api/v1/admin/products/{p['id']}/images/{iid}").status_code==200
    assert not list(admin.MEDIA.rglob('*.jpg'))


def test_validation(editor):
    p,payload=draft(editor)
    assert upload(editor,p['id'],b'bad image').status_code==422
    assert upload(editor,p['id'],b'x'*(8*1024*1024+1)).status_code==413
    payload['price']=-1
    assert editor.put('/api/v1/admin/products/'+p['id'],json=payload).status_code==422


def test_live_page_uses_one_current_script(client):
    html=client.get('/preview/live.html')
    assert 'src="live_script.js?v=0.7.0"' in html.text
    assert 'async function runSearch' not in html.text
    assert html.headers['cache-control']=='no-store'
    js=client.get('/preview/live_script.js').text
    assert "searchBackend='classic', photoDimensions=null, cropArea=null;go" not in js


def test_photo_order_follows_upload_order(editor):
    from io import BytesIO
    from PIL import Image
    p,_=draft(editor)
    photos=[]
    for color in ('red','blue'):
        out=BytesIO();Image.new('RGB',(64,64),color).save(out,'PNG')
        photos.append(('files',(color+'.png',out.getvalue(),'image/png')))
    r=editor.post(f"/api/v1/admin/products/{p['id']}/images",files=photos)
    assert r.status_code==201
    urls=r.json()['images']
    with Image.open(admin.MEDIA/urls[0].removeprefix('/media/products/')) as image:
        red,green,blue=image.getpixel((32,32))
        assert red>200 and blue<20
    with Image.open(admin.MEDIA/urls[1].removeprefix('/media/products/')) as image:
        red,green,blue=image.getpixel((32,32))
        assert blue>200 and red<20
