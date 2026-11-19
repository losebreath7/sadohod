import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "backend" / "media" / "products"
DATABASE_URL = os.environ.get("DATABASE_URL", f"sqlite:///{ROOT / 'backend' / 'sadohod_local.db'}")
DEMO_SEED = os.environ.get("DEMO_SEED", "1") == "1"
SADOHOD_ENV = os.environ.get("SADOHOD_ENV", "development").strip().lower()
if SADOHOD_ENV not in ("development", "staging", "production"):
    raise RuntimeError("Invalid SADOHOD_ENV")
if SADOHOD_ENV != "development" and DEMO_SEED:
    raise RuntimeError("DEMO_SEED must be disabled outside development")
ALLOWED_ORIGINS = [
    value.strip() for value in os.environ.get(
        "ALLOWED_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:3000" if SADOHOD_ENV == "development" else ""
    ).split(",") if value.strip()
]
if SADOHOD_ENV == "production":
    from urllib.parse import urlsplit
    if not DATABASE_URL.startswith("postgresql+psycopg://"):
        raise RuntimeError("Production requires PostgreSQL")
    if os.environ.get("SEARCH_BACKEND", "").lower() != "clip":
        raise RuntimeError("Production requires SEARCH_BACKEND=clip")
    for key in ("SMTP_HOST", "SMTP_FROM", "SMTP_USER", "SMTP_PASSWORD", "ADMIN_TOKEN"):
        value = os.environ.get(key, "")
        if not value or "example." in value.lower() or "replace" in value.lower():
            raise RuntimeError(f"Missing production setting: {key}")
    if len(os.environ["ADMIN_TOKEN"]) < 32:
        raise RuntimeError("ADMIN_TOKEN is too short for production")
    if os.environ.get("SMTP_PORT", "465") not in ("465", "587"):
        raise RuntimeError("Unsupported production SMTP_PORT")
    for value in ALLOWED_ORIGINS:
        uri = urlsplit(value)
        if (uri.scheme != "https" or not uri.hostname
                or uri.hostname.lower() in ("localhost", "127.0.0.1", "10.0.2.2")
                or "example." in uri.hostname.lower() or uri.path or uri.query
                or uri.fragment or uri.username or uri.password):
            raise RuntimeError("Production CORS must contain only exact HTTPS origins")
MAX_UPLOAD_BYTES = 8 * 1024 * 1024
MODEL_ID = "rgb-grid-hist-edges-v1"
FEATURE_DIM = 96
SEARCH_BACKEND = os.environ.get("SEARCH_BACKEND", "classic").lower()
if SEARCH_BACKEND not in ("classic", "clip"):
    raise RuntimeError("SEARCH_BACKEND должен быть classic или clip")

# Conservative starting point, not a calibrated probability. Measure on real photos
# before production rollout. Applies only to OpenCLIP image-image retrieval.
PHOTO_SEARCH_MIN_SCORE = float(os.environ.get("PHOTO_SEARCH_MIN_SCORE", "0.20"))
if not -1.0 <= PHOTO_SEARCH_MIN_SCORE <= 1.0:
    raise RuntimeError("PHOTO_SEARCH_MIN_SCORE должен быть между -1 и 1")
