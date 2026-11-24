from contextlib import asynccontextmanager
import asyncio
import logging
from threading import Event

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .api import router
from .admin import router as admin_router
from .admin_auth import admin_token
from .account import router as account_router
from .buyer_extras import router as buyer_extras_router
from .buyer_reviews_v082 import router as buyer_reviews_router
from .merchant import router as merchant_router, admin_router as merchant_admin_router
from .merchant_operations import router as merchant_operations_router
from .merchant_chat import router as merchant_chat_router
from .moderation import router as moderation_router, admin_router as moderator_staff_router
from .seller_notifications import router as seller_notifications_router
from .product_safety import router as product_safety_router
from .legal_documents import router as legal_router
from .moderation_controls import router as moderation_controls_router
from .buyer_interests import router as buyer_interests_router
from .sadohodets import router as sadohodets_router
from . import buyer_interests_models, sadohodets_models  # noqa: F401
from .moderation_enforcement_models import AccountRestriction, ShopRestriction, ModerationEmail  # noqa: F401
from .config import ALLOWED_ORIGINS, DEMO_SEED, MEDIA, MODEL_ID, ROOT, SEARCH_BACKEND, SADOHOD_ENV
from .database import SessionLocal, init_db
from .build_info import BUILD_INFO
from .seed import seed_demo, ensure_legacy_demo_sale_modes, ensure_demo_category_links
from .photo_seed import seed_photos
from .ml_clip import MODEL_ID as CLIP_MODEL_ID
from .telegram_bridge import run_bridge, configured as telegram_configured


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    admin_token()
    if DEMO_SEED:
        with SessionLocal() as session:
            seed_demo(session)
            seed_photos(session)
            ensure_legacy_demo_sale_modes(session)
            ensure_demo_category_links(session)
    if SEARCH_BACKEND == 'clip':
        # Explicitly selected ML mode: fail loudly if weights are unavailable.
        # Never silently replace the neural model with v0.2 features.
        from .category_inference import text_vectors, toy_text_vectors
        text_vectors()
        toy_text_vectors()
    stop = Event()
    catalog_task = asyncio.create_task(asyncio.to_thread(_refresh_catalog, stop))
    bridge_task = asyncio.create_task(run_bridge()) if telegram_configured() else None
    mail_task = asyncio.create_task(_moderation_mail_loop())
    try:
        yield
    finally:
        stop.set()
        mail_task.cancel()
        try:
            await mail_task
        except asyncio.CancelledError:
            pass
        if bridge_task is not None:
            bridge_task.cancel()
            try:
                await bridge_task
            except asyncio.CancelledError:
                pass

        await catalog_task


def _refresh_catalog(stop):
    from .category_inference import reclassify_indexed_products
    from .ml_index import index_catalog_batch
    while not stop.is_set():
        try:
            with SessionLocal() as session:
                if SEARCH_BACKEND == 'clip':
                    while not stop.is_set():
                        processed, _ = index_catalog_batch(session)
                        if processed == 0:
                            break
                reclassify_indexed_products(session, stop)
            if not stop.is_set():
                logging.getLogger(__name__).info('Catalog refresh complete')
            return
        except Exception:
            logging.getLogger(__name__).exception('Catalog refresh failed')
            stop.wait(30)


async def _moderation_mail_loop():
    from .moderation_email import dispatch_due
    while True:
        try:
            await asyncio.to_thread(dispatch_due, SessionLocal)
        except Exception:
            logging.getLogger(__name__).exception('Moderation email dispatcher failed')
        await asyncio.sleep(30)


app = FastAPI(title="Садоход API", version=BUILD_INFO['full_version'], lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_origin_regex=(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
                        if SADOHOD_ENV == "development" else None),
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)
app.mount("/media/products", StaticFiles(directory=MEDIA), name="media")
app.mount("/preview", StaticFiles(directory=ROOT / "preview", html=True), name="preview")
app.include_router(router)
app.include_router(admin_router)
app.include_router(account_router)
app.include_router(buyer_extras_router)
app.include_router(buyer_reviews_router)
app.include_router(merchant_router)
app.include_router(merchant_admin_router)
app.include_router(merchant_operations_router)
app.include_router(merchant_chat_router)
app.include_router(moderation_router)
app.include_router(moderator_staff_router)
app.include_router(seller_notifications_router)
app.include_router(product_safety_router)
app.include_router(legal_router)
app.include_router(moderation_controls_router)
app.include_router(buyer_interests_router)
app.include_router(sadohodets_router)


@app.get("/health")
def health():
    return {"status": "ok", **BUILD_INFO, "server_patch": BUILD_INFO['build_number'], "photo_categories": SEARCH_BACKEND == "clip", "demo": DEMO_SEED, "search_backend": SEARCH_BACKEND,
            "search_model": MODEL_ID if SEARCH_BACKEND == 'classic' else CLIP_MODEL_ID,
            "catalog_search_pipeline": "r3-taxonomy-multiprompt"}


@app.middleware("http")
async def no_stale_interface(request, call_next):
    response = await call_next(request)
    if request.url.path.startswith(("/preview", "/api/v1/admin", "/api/v1/auth", "/api/v1/account", "/api/v1/merchant", "/health")):
        response.headers["Cache-Control"] = "no-store"
    return response
