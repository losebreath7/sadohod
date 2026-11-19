"""Regression checks for production-visible API configuration."""
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app import main as main_module
from backend.app.config import ALLOWED_ORIGINS


def test_health_reflects_demo_seed_setting(monkeypatch):
    client = TestClient(app)
    monkeypatch.setattr(main_module, "DEMO_SEED", False)
    assert client.get("/health").json()["demo"] is False
    monkeypatch.setattr(main_module, "DEMO_SEED", True)
    assert client.get("/health").json()["demo"] is True


def test_configured_cors_origins_are_respected():
    # Middleware is initialized at import; compare against the configured origin
    # rather than changing environment variables after application startup.
    origin = next(o for o in ALLOWED_ORIGINS if o.strip())
    client = TestClient(app)
    headers = {
        "Origin": origin,
        "Access-Control-Request-Method": "GET",
    }
    response = client.options("/health", headers=headers)
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin

    denied = client.options("/health", headers={
        "Origin": "https://malicious.example",
        "Access-Control-Request-Method": "GET",
    })
    assert "access-control-allow-origin" not in denied.headers
