"""Runs in the isolated tmpfs database from tools/compose.qa.yml."""
import os
import secrets
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from fastapi.testclient import TestClient
from backend.app import buyer_extras, account
from backend.app.config import DATABASE_URL, MEDIA
from backend.app.database import SessionLocal, init_db
from backend.app.main import app
from backend.app.ml_index import index_catalog, nearest_ml_images
from backend.app.seed import seed_demo
from backend.tests.test_ml_index import stub_image_embedding

pytestmark = pytest.mark.skipif(
    os.environ.get('SADOHOD_QA') != '1' or
    DATABASE_URL != 'postgresql+psycopg://qa:qa@qa-db:5432/sadohod_qa',
    reason='requires the dedicated compose.qa.yml database',
)


@pytest.fixture
def pg():
    init_db()
    with SessionLocal() as db:
        seed_demo(db)
    with TestClient(app) as client:
        yield client


def test_pgvector_both_models(pg):
    photo = (MEDIA / 'p02.jpg').read_bytes()
    result = pg.post('/api/v1/search/image', params={'category': 'Сумки', 'limit': 1},
                     files={'file': ('bag.jpg', photo, 'image/jpeg')})
    assert result.status_code == 200, result.text
    assert result.json()['items'][0]['product']['id'] == 'p02'
    with SessionLocal() as db:
        index_catalog(db, embed=stub_image_embedding, model_id='qa-vector')
        rows = nearest_ml_images(db, photo, limit=1, category='Сумки',
                                 embed=stub_image_embedding, model_id='qa-vector')
        assert rows[0][0] == 'i-p02'


def test_pg_same_confirmation_commits_once(pg, monkeypatch):
    codes = {}
    monkeypatch.setenv('SMTP_HOST', 'qa.invalid')
    monkeypatch.setenv('SMTP_FROM', 'support@qa.invalid')
    for module in (account, buyer_extras):
        monkeypatch.setattr(module, 'send_code', lambda mail, code: codes.update({mail: code}))
    prefix = secrets.token_hex(8)
    source, dest = prefix + '@qa.invalid', prefix + '.new@qa.invalid'
    assert pg.post('/api/v1/auth/code', json={'email': source}).status_code == 200
    login = pg.post('/api/v1/auth/verify', json={'email': source, 'code': codes[source]})
    headers = {'Authorization': 'Bearer ' + login.json()['token']}
    assert pg.post('/api/v1/account/email/request', json={'email': dest}, headers=headers).status_code == 200
    ready = Barrier(2, timeout=10)

    def confirm():
        ready.wait()
        return pg.post('/api/v1/account/email/confirm', headers=headers,
                       json={'email': dest, 'code': codes[dest]}).status_code

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(confirm) for _ in range(2)]
        assert sorted(f.result() for f in futures) == [200, 400]
    assert pg.get('/api/v1/account', headers=headers).json()['email'] == dest
