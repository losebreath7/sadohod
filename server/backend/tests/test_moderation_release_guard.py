"""Production moderation guardrail tests.
Synthetic vectors verify routing, not real-world recognition accuracy.
"""
from types import SimpleNamespace

from backend.app import product_screening as screening

REAL_ASSESS = screening.assess
from test_merchant_v080 import env, login, admin_client, photo
from test_instant_publication import setup_seller


def test_classic_safe_text_cannot_publish_unscreened_photo(env, monkeypatch):
    monkeypatch.setattr(screening, "SEARCH_BACKEND", "classic")
    monkeypatch.setattr(screening, "assess", REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    created = client.post("/api/v1/merchant/products", headers=auth,
                          json={"title": "Футболка с принтом пистолета"})
    pid = created.json()["id"]
    assert client.post(f"/api/v1/merchant/products/{pid}/images", headers=auth,
                       files={"files": ("shirt.jpg", photo(), "image/jpeg")}).status_code == 201
    saved = client.put(f"/api/v1/merchant/products/{pid}/save", headers=auth,
        json={"request_id": "moderation-classic-01", "title": "Футболка с принтом пистолета",
              "category": "Одежда", "submit": True,
              "listings": [{"pavilion_id": pavilion, "price": 200, "sale_modes": ["retail"]}]})
    assert saved.status_code == 200, saved.text
    assert saved.json()["status"] == "pending"
    assert saved.json()["listings"][0]["published"] is False
    assert client.get(f"/api/v1/products/{pid}").status_code == 404
    queue = client.get("/api/v1/admin/merchant/queue").json()
    assert pid in {p["id"] for p in queue["products"]}
    # A staff member may clear a legitimate product with the existing panel.
    decision = client.post(f"/api/v1/admin/merchant/products/{pid}/decision",
        json={"decision": "approved", "category": "Одежда"})
    assert decision.status_code == 200, decision.text
    assert client.get(f"/api/v1/products/{pid}").status_code == 200
    # ML triage does not suspend the seller account.
    assert client.get("/api/v1/merchant/me", headers=auth).status_code == 200


def test_classic_approved_photo_replacement_returns_product_to_queue(env, monkeypatch):
    monkeypatch.setattr(screening, "SEARCH_BACKEND", "classic")
    monkeypatch.setattr(screening, "assess", REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    pid = client.post("/api/v1/merchant/products", headers=auth,
                      json={"title": "Куртка"}).json()["id"]
    first = client.post(f"/api/v1/merchant/products/{pid}/images", headers=auth,
                        files={"files": ("a.jpg", photo(), "image/jpeg")})
    assert first.status_code == 201
    saved = client.put(f"/api/v1/merchant/products/{pid}/save", headers=auth,
        json={"request_id": "moderation-replace-01", "title": "Куртка", "category": "Одежда",
              "submit": True, "listings": [{"pavilion_id": pavilion, "price": 500,
                                             "sale_modes": ["retail"]}]})
    assert saved.json()["status"] == "pending"
    assert client.post(f"/api/v1/admin/merchant/products/{pid}/decision",
                       json={"decision": "approved", "category": "Одежда"}).status_code == 200
    assert client.get(f"/api/v1/products/{pid}").status_code == 200
    update = client.post(f"/api/v1/merchant/products/{pid}/images", headers=auth,
        files={"files": ("new.jpg", photo(), "image/jpeg")})
    assert update.status_code == 201, update.text
    assert update.json()["status"] == "pending"
    assert client.get(f"/api/v1/products/{pid}").status_code == 404


def test_classic_never_treats_color_descriptor_as_visual_clearance(monkeypatch):
    monkeypatch.setattr(screening, "SEARCH_BACKEND", "classic")
    item = SimpleNamespace(title="Обычный купальник", description="",
                           images=[SimpleNamespace(id="photo")])
    assert screening._text_reason(item.title, item.description) is None
    assert "classic" in screening.assess(None, item)
    item.title = "Настоящий револьвер"
    assert "оружие" in screening.assess(None, item)


def test_clip_missing_or_nonfinite_prompt_vectors_fail_closed(monkeypatch):
    monkeypatch.setattr(screening, "SEARCH_BACKEND", "clip")
    item = SimpleNamespace(title="Купальник", description="",
                           images=[SimpleNamespace(id="i")])
    db = SimpleNamespace(get=lambda *_: SimpleNamespace(embedding=[1.0] + [0.0] * (screening.DIM - 1)))
    monkeypatch.setattr(screening, "_prompts", lambda: (
        [("оружие", [float("nan")] + [0.0] * (screening.DIM - 1))],
        [[0.0] * screening.DIM]))
    assert "некорректные" in screening.assess(db, item)
    monkeypatch.setattr(screening, "_prompts", lambda: (
        [("оружие", [0.0] * screening.DIM)], [[0.0] * (screening.DIM - 1)]))
    assert "некорректные" in screening.assess(db, item)
    monkeypatch.setattr(screening, "_prompts", lambda: (
        [("оружие", [0.0] * screening.DIM)], [[0.0] * screening.DIM]))
    assert "ML-анализ" in screening.assess(SimpleNamespace(get=lambda *_: None), item)


def test_text_context_exceptions_and_explicit_risk():
    assert screening._text_reason("Игрушечный пистолет", "") is None
    assert screening._text_reason("Футболка с принтом пистолета", "") is None
    assert screening._text_reason("Купальник телесного цвета", "") is None
    assert screening._text_reason("Настоящий пистолет", "футболка с принтом") is not None
    assert screening._text_reason("Наркотик", "это косметика") is not None
    assert screening._text_reason("Кокаин", "футболка с принтом") is not None


def test_visual_triage_for_gun_cannabis_nudity_and_ambiguous_white_powder():
    """Synthetic cosine scores exercise the decision path, not photo accuracy."""
    decide = screening._visual_review_reason
    assert 'оружие' in decide([('оружие', .32), ('запрещённые вещества', .14)], .20)
    assert 'порошок' in decide([('запрещённые вещества', .236), ('оружие', .1)], .27)
    assert 'порошок' in decide([('запрещённые вещества', .29)], .31)
    assert 'нагота' in decide([('нагота', .30)], .22)
    assert decide([('запрещённые вещества', .19)], .30) is None
    assert decide([('запрещённые вещества', .27), ('оружие', .34)], .30) is None or (
        'оружие' in decide([('запрещённые вещества', .27), ('оружие', .34)], .30)
    )
    assert 'некорректные' in decide([('запрещённые вещества', float('nan'))], .20)


def test_drug_photographic_prompts_cover_sachets_and_powders():
    prompts = dict(screening.VISUAL_GROUPS)['запрещённые вещества']
    assert any('white' in prompt and 'powder' in prompt for prompt in prompts)
    assert any('sachet' in prompt or 'ziplock' in prompt for prompt in prompts)


def test_cocaine_text_is_queued_not_public(env, monkeypatch):
    monkeypatch.setattr(screening, 'assess', REAL_ASSESS)
    client, auth, pavilion = setup_seller(env)
    pid = client.post('/api/v1/merchant/products', headers=auth,
        json={'title': 'Пакет кокаина'}).json()['id']
    uploaded = client.post(f'/api/v1/merchant/products/{pid}/images',
        headers=auth, files={'files': ('packet.jpg', photo(), 'image/jpeg')})
    assert uploaded.status_code == 201, uploaded.text
    saved = client.put(f'/api/v1/merchant/products/{pid}/save',
        headers=auth, json={'request_id': 'screen-powder-1', 'title': 'Пакет кокаина',
           'submit': True, 'listings': [{'pavilion_id': pavilion,
            'price': 500, 'sale_modes': ['retail']}]})
    assert saved.status_code == 200, saved.text
    assert saved.json()['status'] == 'pending'
    assert all(not row['published'] for row in saved.json()['listings'])
    assert client.get(f'/api/v1/products/{pid}').status_code == 404



def test_overlay_triage_flags_infographics_but_not_physical_prints():
    """Synthetic CLIP similarities test routing, not actual photo accuracy."""
    review = screening._overlay_review_reason
    assert 'инфографика' in review([.30, .28], [.20, .21])
    assert 'графические' in review([.255], [.23])
    assert review([.27, .28], [.30]) is None  # physical packaging text
    assert review([.20], [.15]) is None
    assert review([.24], [.235]) is None
    assert 'некорректные' in review([float('nan')], [.15])
    assert 'некорректные' in review([], [.15])


def test_overlay_prompts_cover_banners_arrows_collage_and_physical_labels():
    risk = ' '.join(screening.OVERLAY_PROMPTS)
    safe = ' '.join(screening.CLEAN_PHOTO_PROMPTS)
    assert all(word in risk for word in ('banners', 'arrows', 'collage', 'watermark'))
    assert all(word in safe for word in ('packaging', 't-shirt', 'cardboard'))


def test_clip_overlay_review_checks_every_photo_and_does_not_override_safety(monkeypatch):
    """Real assess() uses embeddings from every image and queues overlay review."""
    monkeypatch.setattr(screening, 'SEARCH_BACKEND', 'clip')
    vector_overlay = [1.0] + [0.0] * (screening.DIM - 1)
    vector_clean = [0.0, 1.0] + [0.0] * (screening.DIM - 2)
    vector_zero = [0.0] * screening.DIM
    monkeypatch.setattr(screening, '_prompts', lambda: (
        [('оружие', vector_zero)], [vector_zero]))
    monkeypatch.setattr(screening, '_overlay_prompts', lambda: (
        [vector_overlay], [vector_clean]))
    image_a = SimpleNamespace(id='clean')
    image_b = SimpleNamespace(id='digital-overlays')
    embeds = {'clean': vector_clean, 'digital-overlays': vector_overlay}
    class ImageDb:
        def get(self, model, key):
            return SimpleNamespace(embedding=embeds[key[0]])
    item = SimpleNamespace(title='Футболка', description='',
                           images=[image_a, image_b])
    decision = screening.assess(ImageDb(), item)
    assert 'инфографика' in decision and 'Фото №2' in decision
    assert screening.screening_status(decision) == 'rejected'
    item.images = [image_a]
    assert screening.assess(ImageDb(), item) is None
    item.images = [image_b]
    assert 'инфографика' in screening.assess(ImageDb(), item)
    item.title = 'Настоящий пистолет'
    assert 'оружие' in screening.assess(ImageDb(), item)


def test_clip_overlay_prompt_failure_stays_in_review(monkeypatch):
    monkeypatch.setattr(screening, 'SEARCH_BACKEND', 'clip')
    vector = [1.0] + [0.0] * (screening.DIM - 1)
    monkeypatch.setattr(screening, '_prompts', lambda: (
        [('оружие', [0.0] * screening.DIM)], [[0.0] * screening.DIM]))
    monkeypatch.setattr(screening, '_overlay_prompts', lambda: (
        [[float('nan')] + [0.0] * (screening.DIM - 1)], [vector]))
    item = SimpleNamespace(title='Куртка', description='',
                           images=[SimpleNamespace(id='i')])
    db = SimpleNamespace(get=lambda *_: SimpleNamespace(embedding=vector))
    assert 'инфографики' in screening.assess(db, item)


def test_strong_render_signal_rejects_ambiguous_signal_waits():
    scores = [0.10] * len(screening.OVERLAY_PROMPTS) + [0.34]
    reason = screening._overlay_review_reason(scores, [0.21], 2)
    assert screening.screening_status(reason) == 'rejected'
    assert 'Фото №2' in reason and 'рендер' in reason
    scores[-1] = 0.25
    assert screening.screening_status(screening._overlay_review_reason(scores, [0.23], 2)) == 'pending'


def test_generated_png_refused_before_replacement(env):
    from io import BytesIO
    from PIL import Image, PngImagePlugin

    client, auth, pavilion = setup_seller(env)
    pid = client.post('/api/v1/merchant/products', headers=auth, json={}).json()['id']
    route = f'/api/v1/merchant/products/{pid}/images'
    original = client.post(route, headers=auth, files={'files': ('a.jpg', photo(), 'image/jpeg')})
    images = original.json()['image_items']
    png = BytesIO()
    tags = PngImagePlugin.PngInfo()
    tags.add_text('parameters', 'hat\nSteps: 25, Sampler: Euler, Seed: 12')
    Image.new('RGB', (64, 64)).save(png, 'PNG', pnginfo=tags)
    response = client.post(route, headers=auth, data={'replace_id': images[0]['id']},
                           files={'files': ('a.png', png.getvalue(), 'image/png')})
    assert response.status_code == 422 and 'генератора' in response.json()['detail']
    assert client.get(route.removesuffix('/images'), headers=auth).json()['image_items'] == images


def test_photo_rejection_unpublishes_listing_and_explains_reason(env, monkeypatch):
    from test_contextual_product_screening import _new
    client, auth, pavilion = setup_seller(env)
    pid, body = _new(client, auth, pavilion, 'Набор', 'photo-policy-live')
    path = f'/api/v1/merchant/products/{pid}'
    assert client.put(path + '/save', headers=auth, json=body).json()['status'] == 'approved'
    reason = screening._overlay_review_reason([0.36], [0.21], 2)
    monkeypatch.setattr(screening, 'assess', lambda db, product: reason)
    result = client.post(path + '/images', headers=auth, files={'files': ('b.jpg', photo(), 'image/jpeg')})
    assert result.status_code == 201
    assert result.json()['status'] == 'rejected'
    assert result.json()['listings'][0]['status'] == 'rejected'
    assert result.json()['note'] == reason
    assert client.get(f'/api/v1/products/{pid}').status_code == 404
