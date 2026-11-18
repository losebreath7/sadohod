import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "backend" / "media" / "products"
DATABASE_URL = os.environ.get("DATABASE_URL", f"sqlite:///{ROOT / 'backend' / 'sadohod_local.db'}")
DEMO_SEED = os.environ.get("DEMO_SEED", "1") == "1"
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000").split(",")
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
