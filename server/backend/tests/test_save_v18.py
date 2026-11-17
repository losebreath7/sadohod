from sqlalchemy import select
from backend.app.models import Product, ProductImage
from backend.app.merchant_models import MerchantListing
from test_merchant_v080 import env, login, applicant, admin_client, approve, photo


def owner(env):
    c, codes, factory, media = env
    auth = login(c,codes,'save18@test.com'); admin_client(c)
    approve(c,'applications/'+applicant(c,'save18',auth)+'/decision')
    pavilion = c.get('/api/v1/merchant/pavilions',headers=auth).json()['items'][0]['id']
    return c, auth, pavilion, factory, media


def draft(c,auth):
    return c.post('/api/v1/merchant/products',headers=auth,json={'request_id':'create-test-18','title':'Худи'}).json()['id']


def upload(c,auth,pid,key='upload-test-18',replace=None,data=None):
    body={'request_id':key}
    if replace: body['replace_id']=replace
    return c.post(f'/api/v1/merchant/products/{pid}/images',headers=auth,data=body,
                  files={'files':('photo.jpg',photo() if data is None else data,'image/jpeg')})


def test_create_upload_save_retries_do_not_duplicate(env):
    c,auth,pavilion,factory,_=owner(env)
    pid=draft(c,auth)
    assert draft(c,auth)==pid
    first=upload(c,auth,pid)
    assert first.status_code==201,first.text
    assert len(upload(c,auth,pid).json()['images'])==1
    body={'request_id':'final-test-18','title':'Худи','category':'','listings':[
          {'pavilion_id':pavilion,'price':3500,'sale_modes':['retail']}],'submit':True}
    for _ in range(2):
        r=c.put(f'/api/v1/merchant/products/{pid}/save',headers=auth,json=body)
        assert r.status_code==200,r.text
        assert r.json()['status']=='approved'
    assert upload(c,auth,pid).status_code==201  # lost upload response can be replayed after submit
    assert c.get('/api/v1/products/'+pid).status_code==200
    with factory() as db:
        assert db.query(Product).count()==1
        assert db.query(ProductImage).count()==1
        assert db.query(MerchantListing).count()==1
    assert c.get('/api/v1/products/'+pid).json()['price']==3500


def test_invalid_replacement_retains_original_and_retry_is_safe(env):
    c,auth,_,factory,media=owner(env); pid=draft(c,auth)
    item=upload(c,auth,pid).json()['image_items'][0]
    path=media/item['url'].removeprefix('/media/products/')
    assert upload(c,auth,pid,'replace-test-18',item['id'],b'broken').status_code==422
    assert path.exists()
    current=c.get(f'/api/v1/merchant/products/{pid}',headers=auth).json()
    assert current['image_items'][0]['id']==item['id']
    result=upload(c,auth,pid,'replace-test-18',item['id'])
    assert result.status_code==201,result.text
    assert result.json()['image_items'][0]['id']!=item['id']
    assert not path.exists()
    assert len(upload(c,auth,pid,'replace-test-18',item['id']).json()['images'])==1


def test_failed_save_is_atomic_and_changed_receipt_rejected(env):
    c,auth,pavilion,_,_=owner(env); pid=draft(c,auth); upload(c,auth,pid)
    body={'request_id':'atomic-save-18','title':'Другое название','listings':[
          {'pavilion_id':pavilion,'price':123,'sale_modes':['retail']},
          {'pavilion_id':'foreign','price':123,'sale_modes':['retail']} ]}
    assert c.put(f'/api/v1/merchant/products/{pid}/save',headers=auth,json=body).status_code==403
    current=c.get(f'/api/v1/merchant/products/{pid}',headers=auth).json()
    assert current['title']=='Худи' and current['listings']==[]
    body['listings']=body['listings'][:1]
    assert c.put(f'/api/v1/merchant/products/{pid}/save',headers=auth,json=body).status_code==200
    body['listings'][0]['price']=999
    assert c.put(f'/api/v1/merchant/products/{pid}/save',headers=auth,json=body).status_code==409
