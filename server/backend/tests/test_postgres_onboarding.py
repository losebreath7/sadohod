"""Concurrent seller requests, only on the dedicated QA PostgreSQL database."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import uuid

from backend.tests.test_postgres_search_change import pg, pytestmark
from backend.app import account
from backend.app.main import app
from backend.app.admin_auth import require_admin


def test_same_application_and_resubmission_are_single_records(pg, monkeypatch):
    codes = {}
    monkeypatch.setenv('SMTP_HOST', 'qa.invalid')
    monkeypatch.setenv('SMTP_FROM', 'qa@qa.invalid')
    monkeypatch.setattr(account, 'send_code', lambda email, code: codes.update({email: code}))
    email = uuid.uuid4().hex + '@qa.invalid'
    assert pg.post('/api/v1/auth/code', json={'email':email}).status_code == 200
    login = pg.post('/api/v1/auth/verify', json={'email':email,'code':codes[email]})
    auth = {'Authorization':'Bearer ' + login.json()['token']}
    body = {'shop_name':'Тест', 'zone':'QA', 'code':uuid.uuid4().hex}

    def pair(method, path, body):
        ready = Barrier(2, timeout=10)
        def submit(_):
            ready.wait()
            return pg.request(method, path, headers=auth, json=body)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(submit, range(2)))
        assert all(r.status_code in (200, 201) for r in results), [r.text for r in results]
        assert results[0].json()['id'] == results[1].json()['id']
        return results[0].json()['id']

    aid = pair('POST', '/api/v1/merchant/applications', body)
    assert len(pg.get('/api/v1/merchant/me', headers=auth).json()['applications']) == 1
    app.dependency_overrides[require_admin] = lambda: None
    try:
        url = f'/api/v1/admin/merchant/applications/{aid}/decision'
        assert pg.post(url, json={'decision':'rejected','note':'Исправьте адрес'}).status_code == 200
        body['code'] = uuid.uuid4().hex
        assert pair('PUT', f'/api/v1/merchant/applications/{aid}', body) == aid
        assert pg.post(url, json={'decision':'approved'}).status_code == 200
        body = {'zone':'QA','code':uuid.uuid4().hex}
        rid = pair('POST', '/api/v1/merchant/pavilions', body)
        assert len(pg.get('/api/v1/merchant/pavilions', headers=auth).json()['requests']) == 1
        url = f'/api/v1/admin/merchant/pavilions/{rid}/decision'
        assert pg.post(url, json={'decision':'rejected'}).status_code == 200
        body['code'] = uuid.uuid4().hex
        assert pair('PUT', f'/api/v1/merchant/pavilions/requests/{rid}', body) == rid
    finally:
        app.dependency_overrides.pop(require_admin, None)
