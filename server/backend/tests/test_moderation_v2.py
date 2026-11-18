"""Moderation v2: deterministic routing regression tests.

Visual cases use synthetic CLIP vectors to test routing, not recognition
quality. A separately labelled real-photo benchmark is required for rollout.
"""
from types import SimpleNamespace

from backend.app import product_screening as s
from test_instant_publication import setup_seller
from test_merchant_v080 import env, photo


def _publish(client, auth, pavilion, title, key, description=''):
    created = client.post('/api/v1/merchant/products', headers=auth,
                          json={'title': title}).json()
    pid = created['id']
    uploaded = client.post(f'/api/v1/merchant/products/{pid}/images',
        headers=auth, files={'files': ('item.jpg', photo(), 'image/jpeg')})
    assert uploaded.status_code == 201, uploaded.text
    result = client.put(f'/api/v1/merchant/products/{pid}/save', headers=auth,
        json={'request_id': key, 'title': title, 'description': description,
              'submit': True, 'listings': [{'pavilion_id': pavilion,
                                           'price': 300, 'sale_modes': ['retail']}]})
    assert result.status_code == 200, result.text
    return pid, result.json()


def test_restricted_substances_are_queued_before_publication(env):
    client, auth, pavilion = setup_seller(env)
    pid, result = _publish(client, auth, pavilion, 'Кокаин', 'v2-drugs-01')
    assert result['status'] == 'pending'
    assert result['listings'][0]['published'] is False
    assert client.get('/api/v1/products/' + pid).status_code == 404
    queue = client.get('/api/v1/admin/merchant/queue').json()
    assert any(item['id'] == pid for item in queue['products'])


def test_explicit_adult_content_is_sent_to_review(env):
    client, auth, pavilion = setup_seller(env)
    pid, result = _publish(client, auth, pavilion,
                           'Порнографические материалы', 'v2-adult-01')
    assert result['status'] == 'pending'
    assert client.get('/api/v1/products/' + pid).status_code == 404


def test_safe_apparel_is_published_in_classic_mode(env):
    client, auth, pavilion = setup_seller(env)
    pid, result = _publish(client, auth, pavilion,
                           'Футболка с принтом пистолета', 'v2-shirt-01')
    assert result['status'] == 'approved'
    assert client.get('/api/v1/products/' + pid).status_code == 200


def test_context_exceptions_do_not_hide_explicit_real_weapon():
    assert s._text_reason('Настоящий пистолет',
                          'В комплекте футболка с принтом') is not None
    assert s._text_reason('Футболка с принтом пистолета', '') is None
    assert s._text_reason('Купальник телесного цвета', '') is None
    assert s._text_reason('Порошок для стирки', '') is None
    assert s._text_reason('Кокаин', 'футболка с принтом') is not None
    assert s._text_reason('Рецептурный препарат', '') is not None
    assert s._text_reason('Поддельный паспорт', '') is not None
    assert s._text_reason('Боди на манекене', '') is None


def test_missing_ml_embedding_goes_to_staff(monkeypatch):
    monkeypatch.setattr(s, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(s, '_prompts', lambda: ([('оружие', [1.0] * s.DIM)],
                                              [[0.0] * s.DIM]))
    image = SimpleNamespace(id='image-1')
    db = SimpleNamespace(get=lambda *args: None)
    product = SimpleNamespace(title='Товар', description='', images=[image])
    assert 'ML-анализ' in s.assess(db, product)


def test_ml_flags_each_photo_not_just_first(monkeypatch):
    monkeypatch.setattr(s, 'SEARCH_BACKEND', 'clip')
    vector = [0.0] * s.DIM
    vector[0] = 1.0
    monkeypatch.setattr(s, '_prompts', lambda: ([('опасные вещества', [1.0] + [0.0] * (s.DIM - 1))],
                                              [[0.0] * s.DIM]))
    images = [SimpleNamespace(id='one'), SimpleNamespace(id='two')]
    db = SimpleNamespace(get=lambda _cls, key: SimpleNamespace(
        embedding=[0.0] * s.DIM if key[0] == 'one' else vector))
    product = SimpleNamespace(title='Товар', description='', images=images)
    assert 'опасные вещества' in s.assess(db, product)


def test_ml_unavailable_fails_to_review(monkeypatch):
    monkeypatch.setattr(s, 'SEARCH_BACKEND', 'clip')
    monkeypatch.setattr(s, '_prompts', lambda: (_ for _ in ()).throw(RuntimeError('offline')))
    product = SimpleNamespace(title='Товар', description='', images=[SimpleNamespace(id='one')])
    assert 'недоступен' in s.assess(None, product)
