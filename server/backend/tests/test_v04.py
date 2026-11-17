from io import BytesIO
from PIL import Image
from sqlalchemy import select, func, create_engine
from sqlalchemy.orm import Session
from backend.tests.test_api import client
from backend.app.config import MEDIA
from backend.app.database import Base
from backend.app.models import Product
from backend.app.seed import seed_demo
from backend.app.photo_seed import seed_photos


def test_photo_migration_is_additive_and_idempotent(monkeypatch, tmp_path):
    # Keep the fixture hermetic: real catalog photos aren't stored in Git.
    import json
    from backend.app import photo_seed
    manifest = json.loads((photo_seed.ROOT / 'demo_data/photo_catalog.json').read_text(encoding='utf-8'))
    data = BytesIO()
    Image.new('RGB', (32, 32), (90, 140, 185)).save(data, format='JPEG')
    for row in manifest:
        if row['split'] == 'catalog':
            (tmp_path / row['filename']).write_bytes(data.getvalue())
    monkeypatch.setattr(photo_seed, 'MEDIA', tmp_path)
    engine=create_engine('sqlite://')
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        seed_demo(db)
        db.get(Product,'p01').title='Existing custom title'
        db.commit()
        assert seed_photos(db)==240
        assert seed_photos(db)==0
        assert db.scalar(select(func.count(Product.id)))==252
        assert db.get(Product,'p01').title=='Existing custom title'


def test_optional_photo_dataset_absent_keeps_seed_products(monkeypatch, tmp_path):
    from backend.app import photo_seed
    monkeypatch.setattr(photo_seed, 'MEDIA', tmp_path)
    engine = create_engine('sqlite://')
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        seed_demo(db)
        assert seed_photos(db) == 0
        assert seed_photos(db) == 0
        assert db.scalar(select(func.count(Product.id))) == 12

def test_threshold_category_and_crop_reach_search(monkeypatch, client):
    from backend.app import api, ml_index
    monkeypatch.setattr(api,'SEARCH_BACKEND','clip')
    seen=[]
    def retrieve(session,data,limit,category=None,category_ids=None):
        seen.append(Image.open(BytesIO(data)).size)
        if category == 'Сумки':
            return [('i-p02',.7)]
        return [('i-p01',.9),('i-p02',.7),('i-p09',.6)]
    monkeypatch.setattr(ml_index,'nearest_ml_images',retrieve)
    data=(MEDIA/'p01.jpg').read_bytes()
    size=Image.open(BytesIO(data)).size
    args={'files':{'file':('q.jpg',data,'image/jpeg')},'data':{'crop':'0,0,0.5,0.5'}}
    result=client.post('/api/v1/search/image?category=Сумки&min_score=0.65&limit=1',**args).json()
    assert result['crop_applied'] is True
    assert result['items'][0]['product']['id']=='p02'
    assert len(result['items'])==1
    assert seen[0]==(round(size[0]*.5),round(size[1]*.5))
    empty=client.post('/api/v1/search/image?min_score=0.95',**args).json()
    assert empty['items']==[]
    assert 'Нет товаров' in empty['notice']
    assert client.post('/api/v1/search/image?min_score=nan',**args).status_code==422
