"""Regression checks for login behavior used by the iPhone HTTPS client.

The backend accepts concurrent sessions for the same buyer. A rejected resend
must not revoke an existing account session or delete data.
"""

from backend.tests.test_account import setup, login  # reuse isolated SQLite fixture


def test_same_email_has_independent_sessions(setup):
    client, codes, _ = setup
    first = login(client, codes, 'same@example.com')
    second = login(client, codes, 'same@example.com')
    assert first != second
    assert client.get('/api/v1/account', headers=first).status_code == 200
    assert client.get('/api/v1/account', headers=second).status_code == 200
    assert client.post('/api/v1/auth/logout', headers=second).status_code == 200
    assert client.get('/api/v1/account', headers=first).status_code == 200
    assert client.get('/api/v1/account', headers=second).status_code == 401


def test_code_rate_limit_has_retry_after_without_revealing_account(setup):
    client, codes, _ = setup
    # Cooldown may reject earlier requests; repeated requests still increment
    # rate buckets. Once the email bucket reaches its limit, return retry info.
    for _ in range(5):
        client.post('/api/v1/auth/code', json={'email':'limit@example.com'})
    response = client.post('/api/v1/auth/code', json={'email':'limit@example.com'})
    assert response.status_code == 429
    assert int(response.headers['retry-after']) > 0
    assert 'limit@example.com' not in response.text
