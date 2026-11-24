"""Profile publication, authorization and account deletion regressions."""
from backend.tests.test_account import setup, login  # noqa: F401

ROOT = '/api/v1/sadohodets/me'


def test_profile_lifecycle_and_isolation(setup):
    c, codes, sessions = setup
    a = login(c, codes, 'courier-a@example.com')
    b = login(c, codes, 'courier-b@example.com')
    assert c.get(ROOT).status_code == 401
    assert c.get(ROOT, headers=a).status_code == 404
    r = c.put(ROOT, headers=a, json={'name': 'Анна'})
    assert r.status_code == 200, r.text
    assert not r.json()['published']
    assert c.get(ROOT, headers=b).status_code == 404
    assert c.put(ROOT+'/publication', headers=a, json={'published': True}).status_code == 422
    for contacts in ({'unknown': 'x'}, {'website': 'javascript:alert(1)'}, {'phone': 'abc'}):
        assert c.put(ROOT, headers=a, json={'name': 'Анна', 'contacts': contacts}).status_code == 422
    r = c.put(ROOT, headers=a, json={'name': 'Анна', 'contacts': {'telegram': '@courier_a'}})
    assert r.status_code == 200, r.text
    assert r.json()['contacts']['telegram'] == 'https://t.me/courier_a'
    assert c.put(ROOT+'/publication', headers=a, json={'published': True}).json()['published']
    assert not c.put(ROOT, headers=a, json={'name': 'Анна'}).json()['published']
    assert c.delete(ROOT, headers=a).status_code == 200
    assert c.get('/api/v1/account', headers=a).status_code == 200
    assert c.get(ROOT, headers=a).status_code == 404


def test_full_account_deletion_cleans_profile(setup):
    from backend.app.sadohodets_models import SadohodetsProfile
    c, codes, sessions = setup
    a = login(c, codes, 'courier-delete@example.com')
    r = c.put(ROOT, headers=a, json={'name': 'Анна'})
    assert r.status_code == 200, r.text
    buyer_id = r.json()['id']
    assert c.delete('/api/v1/account', headers=a).status_code == 200
    with sessions() as db:
        assert db.get(SadohodetsProfile, buyer_id) is None
