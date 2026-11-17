from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.config import MEDIA
from backend.app.database import Base, get_db
from backend.app.main import app
from backend.app.seed import seed_demo


@pytest.fixture
def client():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    make_session = sessionmaker(engine, expire_on_commit=False)
    with make_session() as db:
        seed_demo(db)

    def db_override():
        with make_session() as db:
            yield db

    app.dependency_overrides[get_db] = db_override
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


def test_catalog_product_seller(client):
    response = client.get("/api/v1/products")
    assert response.status_code == 200
    assert len(response.json()["items"]) == 12
    assert response.json()["items"][0]["offers"]
    assert client.get("/api/v1/products/p01").json()["seller_id"] == "s01"
    assert len(client.get("/api/v1/sellers/s01").json()["products"]) == 3
    assert client.get("/api/v1/products/missing").status_code == 404
    assert len(client.get("/api/v1/products", params={"category": "Обувь"}).json()["items"]) == 2


def test_visual_search_changes_ranking(client):
    r1 = client.post("/api/v1/search/image", files={"file": ("jacket.jpg", (MEDIA / "p01.jpg").read_bytes(), "image/jpeg")})
    r2 = client.post("/api/v1/search/image", files={"file": ("bag.jpg", (MEDIA / "p02.jpg").read_bytes(), "image/jpeg")})
    assert r1.status_code == 200, r1.text
    assert r2.status_code == 200, r2.text
    assert r1.json()["items"][0]["product"]["id"] == "p01"
    assert r2.json()["items"][0]["product"]["id"] == "p02"
    assert r1.json()["items"][0]["score"] != r2.json()["items"][0]["score"] or r1.json()["items"][1]["product"]["id"] != r2.json()["items"][1]["product"]["id"]


def test_invalid_files(client):
    r = client.post("/api/v1/search/image", files={"file": ("bad.jpg", b"invalid", "image/jpeg")})
    assert r.status_code == 422
    r = client.post("/api/v1/search/image", files={"file": ("huge.jpg", b"a" * (8*1024*1024+1), "image/jpeg")})
    assert r.status_code == 413


def test_image_search_crop_endpoint(client):
    data = (MEDIA / 'p01.jpg').read_bytes()
    success = client.post('/api/v1/search/image', data={'crop': '0.2,0.2,0.6,0.6'},
                          files={'file': ('query.jpg', data, 'image/jpeg')})
    assert success.status_code == 200
    assert success.json()['model'] == 'rgb-grid-hist-edges-v1'
    failed = client.post('/api/v1/search/image', data={'crop': '0.98,0.98,0.5,0.5'},
                         files={'file': ('query.jpg', data, 'image/jpeg')})
    assert failed.status_code == 422


def test_ml_endpoint_reports_truthful_model(monkeypatch, client):
    from backend.app import api, ml_index
    monkeypatch.setattr(api, 'SEARCH_BACKEND', 'clip')
    # Mock embedding retrieval tests HTTP wiring, not OpenCLIP model quality.
    monkeypatch.setattr(ml_index, 'nearest_ml_images', lambda session, data, limit, category=None, category_ids=None: [('i-p02', 0.72)])
    result = client.post('/api/v1/search/image',
                         files={'file': ('bag.jpg', (MEDIA / 'p02.jpg').read_bytes(), 'image/jpeg')})
    assert result.status_code == 200
    body = result.json()
    assert body['method'] == 'openclip_image_embedding'
    assert body['model'].startswith('openclip-')
    assert body['items'][0]['product']['id'] == 'p02'
    assert 'OpenCLIP' in body['notice']


def test_search_quota_precedes_body_parsing(client, monkeypatch):
    from backend.app import api
    from fastapi import HTTPException

    def exhausted(session, key, maximum, window):
        assert key.startswith('photo-ip:') and maximum == 20 and window == 60
        raise HTTPException(429, 'Лимит', headers={'Retry-After': '4'})

    monkeypatch.setattr(api, 'rate_limit', exhausted)
    response = client.post('/api/v1/search/image', content=b'')
    assert response.status_code == 429 and response.headers['retry-after'] == '4'
