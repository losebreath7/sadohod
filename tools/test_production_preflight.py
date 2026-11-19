"""Production preflight negative cases and isolation contract (no Docker required)."""
from pathlib import Path
import tempfile

from check_production_env import parse_env, validate

ROOT = Path(__file__).resolve().parents[1]
GOOD = {
    "SADOHOD_ENV": "production",
    "DEMO_SEED": "0",
    "API_DOMAIN": "api.sadohod.ru",
    "POSTGRES_PASSWORD": "a" * 64,
    "ADMIN_TOKEN": "z" * 48,
    "SMTP_HOST": "smtp.mail.ru",
    "SMTP_PORT": "465",
    "SMTP_FROM": "no-reply@sadohod.ru",
    "SMTP_USER": "no-reply@sadohod.ru",
    "SMTP_PASSWORD": "Q" * 24,
    "ALLOWED_ORIGINS": "https://sadohod.ru,https://seller.sadohod.ru",
    "PHOTO_SEARCH_MIN_SCORE": "0.20",
}


def rejects(**changes):
    value = dict(GOOD, **changes)
    try:
        validate(value)
    except ValueError:
        return
    raise AssertionError("Unsafe production variables unexpectedly passed")


def test_preflight():
    validate(GOOD)
    rejects(DEMO_SEED="1")
    rejects(SADOHOD_ENV="development")
    rejects(API_DOMAIN="api.example.com")
    rejects(API_DOMAIN="localhost")
    rejects(API_DOMAIN="127.0.0.1")
    rejects(POSTGRES_PASSWORD="local-dev-only")
    rejects(POSTGRES_PASSWORD="")
    rejects(ADMIN_TOKEN="test")
    rejects(SMTP_HOST="")
    rejects(SMTP_PORT="25")
    rejects(SMTP_PASSWORD="")
    rejects(SMTP_FROM="no-reply@example.com")
    rejects(ALLOWED_ORIGINS="http://localhost:3000")
    rejects(ALLOWED_ORIGINS="https://sadohod.ru,https://evil.invalid")
    rejects(ALLOWED_ORIGINS="*")
    rejects(SADOHOD_BIND="0.0.0.0")
    rejects(USE_LOCAL_DEMO="1")
    rejects(DATABASE_URL="sqlite:///sample.db")
    rejects(TELEGRAM_BOT_TOKEN="token-only")
    with tempfile.TemporaryDirectory() as folder:
        p = Path(folder) / ".env"
        p.write_text("SADOHOD_ENV=production\nSADOHOD_ENV=development\n")
        try:
            parse_env(p)
        except ValueError:
            pass
        else:
            raise AssertionError("Duplicate production keys not rejected")


def test_production_does_not_reuse_local_volumes():
    compose = (ROOT / "docker-compose.production.yml").read_text()
    local = (ROOT / "docker-compose.yml").read_text()
    assert "sadohod_mvp_v0_2" in local
    assert "name: sadohod_public" in compose
    assert "docker-compose.yml" not in compose
    assert "backend/Dockerfile.production" in compose
    assert "DEMO_SEED" in compose and "SEARCH_BACKEND: clip" in compose
    assert '"80:80"' in compose and '"443:443"' in compose
    db_section = compose.split("\n  db:", 1)[1].split("\n  api:", 1)[0]
    api_section = compose.split("\n  api:", 1)[1].split("\n  https:", 1)[0]
    assert "\n    ports:" not in db_section
    assert "\n    ports:" not in api_section
    assert "internal: true" in compose
    image = (ROOT / "server/backend/Dockerfile.production").read_text()
    assert "COPY demo_data" not in image
    shared = (ROOT / "shared/flutter_core/lib/api_base_url.dart").read_text()
    assert "kReleaseMode && !kIsWeb" in shared
    assert "Release builds require explicit public HTTPS" in shared


if __name__ == "__main__":
    test_preflight()
    test_production_does_not_reuse_local_volumes()
    print("Production preflight and isolation checks: OK")
