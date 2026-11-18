import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "backend" / "media" / "products"
DATABASE_URL = os.environ.get("DATABASE_URL", f"sqlite:///{ROOT / 'backend' / 'sadohod_local.db'}")
DEMO_SEED = os.environ.get("DEMO_SEED", "1") == "1"
SADOHOD_ENV = os.environ.get("SADOHOD_ENV", "development").strip().lower()
if SADOHOD_ENV not in ("development", "staging", "production"):
    raise RuntimeError("SADOHOD_ENV должен быть development, staging или production")
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000").split(",")
    if origin.strip()
]
if SADOHOD_ENV != "development" and DEMO_SEED:
    raise RuntimeError("В staging/production необходимо отключить DEMO_SEED")

MAX_UPLOAD_BYTES = 8 * 1024 * 1024
MODEL_ID = "rgb-grid-hist-edges-v1"
FEATURE_DIM = 96
SEARCH_BACKEND = os.environ.get("SEARCH_BACKEND", "classic").lower()
if SEARCH_BACKEND not in ("classic", "clip"):
    raise RuntimeError("SEARCH_BACKEND должен быть classic или clip")
