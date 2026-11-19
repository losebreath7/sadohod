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
