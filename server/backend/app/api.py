from threading import BoundedSemaphore
import os

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select, or_
from sqlalchemy.orm import Session, selectinload

from .config import MODEL_ID, SEARCH_BACKEND, PHOTO_SEARCH_MIN_SCORE
from .database import get_db
from .image_features import InvalidImage
from .models import Offer, OfferSaleModes, Product, ProductImage, Seller, ProductDetails, Pavilion
from .account import digest, rate_limit
from .search_upload import read_search_photo
from .search import nearest_images, SearchCapacityError
from .crop import crop_image
from .ml_clip import MODEL_ID as CLIP_MODEL_ID
from .merchant_models import ProductCategoryAssignment
from .catalog_taxonomy import NODES_V1, BY_ID, category_path, descendant_ids
from .text_search import (text_filter, visual_product_ids, precise_query_leaves,
                          primary_type_conflicts)

router = APIRouter(prefix="/api/v1")


def serialize_seller(seller: Seller) -> dict:
    return {"id": seller.id, "name": seller.name, "pavilion": seller.pavilion.code, "zone": seller.pavilion.zone, "demo": seller.details.is_demo if seller.details else True, "contact": seller.details.contact if seller.details else ""}


def serialize_sale_modes(offer: Offer) -> list[str]:
    modes = offer.modes
    if modes is None:
        return []  # Legacy offer: no verified modes; never invent them.
    return (["wholesale"] if modes.wholesale else []) + (["retail"] if modes.retail else [])


def serialize_product(product: Product) -> dict:
    offers = sorted(product.offers, key=lambda item: (item.price is None, item.price if item.price is not None else 0, item.id))
    offer = offers[0] if offers else None
    images = sorted(product.images, key=lambda item: (item.ordering.position if item.ordering else -1, item.id))
    assigned = product.category_assignment
    return {
        "id": product.id, "title": product.title, "category": product.category,
        "category_id": assigned.category_id if assigned else None,
        "category_path": category_path(assigned.category_id) if assigned else [],
        "search_tags": sorted({tag.tag for tag in product.search_tags}),
        "description": product.description, "colors": product.colors,
        "sizes": product.details.sizes if product.details else [],
        "active": product.details.active if product.details else True,
        "price": offer.price if offer else None,
        "seller_id": offer.seller_id if offer else None,
        "sale_modes": serialize_sale_modes(offer) if offer else [],
        "image": f"/media/products/{images[0].filename}" if images else None,
        "images": [f"/media/products/{image.filename}" for image in images],
        "image_records": [{"id": image.id, "url": f"/media/products/{image.filename}"} for image in images],
        "offers": [{"id": o.id, "price": o.price, "seller": serialize_seller(o.seller),
                    "pavilion": {"id": o.pavilion.id, "code": o.pavilion.code, "zone": o.pavilion.zone},
                    "sale_modes": serialize_sale_modes(o)} for o in offers],
        "demo": product.is_demo,
    }


def visible_products():
    return ~Product.id.in_(select(ProductDetails.product_id).where(ProductDetails.active.is_(False)))


def product_query(include_hidden=False):
    statement = select(Product)
    if not include_hidden:
        statement = statement.where(visible_products())
    return statement.options(
        selectinload(Product.details),
        selectinload(Product.category_assignment),
        selectinload(Product.search_tags),
        selectinload(Product.images).selectinload(ProductImage.ordering),
        selectinload(Product.offers).joinedload(Offer.seller).joinedload(Seller.pavilion),
        selectinload(Product.offers).selectinload(Offer.modes),
    )


@router.get("/categories")
def categories(session: Session = Depends(get_db)):
    rows = session.scalars(select(Product.category).where(visible_products()).distinct().order_by(Product.category)).all()
    return {"items": ["Все", *rows], "demo": True}


@router.get("/categories/tree")
def category_tree():
    """Complete stable taxonomy; clients use IDs to avoid duplicate leaf labels."""
    return {'items': [
        {'id': id, 'parent_id': parent, 'name': name,
         'path': category_path(id), 'position': position}
        for position, (id, parent, name) in enumerate(NODES_V1)
    ]}


def category_ids_for_filter(value: str | None):
    if not value or value == 'Все':
        return []
    roots = [value] if value in BY_ID else [
        item_id for item_id, _, name in NODES_V1 if name == value]
    return sorted({descendant for root in roots for descendant in descendant_ids(root)})


def product_category_filter(value):
    ids = category_ids_for_filter(value)
    # Legacy string filter remains valid, including custom categories.
    if not ids:
        return Product.category == value
    return or_(Product.category == value,
               Product.id.in_(
                   select(ProductCategoryAssignment.product_id).where(
                       ProductCategoryAssignment.category_id.in_(ids))))


@router.get("/products")
def products(category: str | None = None, q: str = "", limit: int = Query(default=100, ge=1, le=500),
             offset: int = Query(default=0, ge=0), session: Session = Depends(get_db)):
    statement = product_query().order_by(Product.id)
    if category and category != "Все":
        statement = statement.where(product_category_filter(category))
    if q.strip():
        statement = statement.where(text_filter(q))
    items = session.scalars(statement.offset(offset).limit(limit)).all()
    return {"items": [serialize_product(p) for p in items], "limit": limit, "offset": offset, "demo": True}


def search_sellers(session: Session, query: str, limit: int = 30) -> list[dict]:
    """Search public shop names and approved pavilion codes, independently of products.

    Unicode casefold is intentionally done in Python: SQLite lower()/LIKE does
    not reliably fold Cyrillic. Read only public metadata, not product images.
    """
    import time
    import unicodedata
    from .merchant_models import PavilionClaim, ShopMembership
    from .moderation_enforcement_models import ShopRestriction, AccountRestriction

    def normalized(value):
        value = unicodedata.normalize('NFKC', value or '').casefold().replace('ё', 'е')
        return ' '.join(value.replace('–', '-').replace('—', '-').split())

    needle = normalized(query)
    if not needle:
        return []
    now = time.time()
    blocked_shops = select(ShopRestriction.seller_id).where(
        ShopRestriction.active.is_(True),
        or_(ShopRestriction.until.is_(None), ShopRestriction.until > now))
    blocked_owners = select(ShopMembership.seller_id).join(
        AccountRestriction, AccountRestriction.buyer_id == ShopMembership.buyer_id
    ).where(ShopMembership.role == 'owner', AccountRestriction.active.is_(True),
            or_(AccountRestriction.until.is_(None), AccountRestriction.until > now))
    public = (Seller.id.not_in(blocked_shops), Seller.id.not_in(blocked_owners))
    columns = (Seller.id, Seller.name, Pavilion.code, Pavilion.zone)
    primary = select(*columns).join(Pavilion, Pavilion.id == Seller.pavilion_id).where(*public)
    claims = select(*columns).join(PavilionClaim, PavilionClaim.seller_id == Seller.id).join(
        Pavilion, Pavilion.id == PavilionClaim.pavilion_id).where(*public)
    by_id = {}
    for sid, name, code, zone in session.execute(primary.union(claims)):
        entry = by_id.setdefault(sid, {'id': sid, 'name': name, 'addresses': set(), 'matches': []})
        entry['addresses'].add(code)
        fields = (normalized(name), normalized(code), normalized(f'{zone} {code}'))
        # Exact shop name, then name prefix, then other literal matches.
        rank = 0 if needle == fields[0] else 1 if fields[0].startswith(needle) else (
            2 if needle == fields[1] else 3 if any(needle in field for field in fields) else None)
        if rank is not None:
            entry['matches'].append((rank, code, zone))
    ranked = []
    for entry in by_id.values():
        if not entry['matches']:
            continue
        rank, code, zone = min(entry['matches'])
        ranked.append((rank, normalized(entry['name']), entry['id'], {
            'id': entry['id'], 'name': entry['name'], 'pavilion': code, 'zone': zone,
            'pavilions': sorted(entry['addresses']),
        }))
    ranked.sort(key=lambda item: item[:3])
    return [item[3] for item in ranked[:limit]]


@router.get("/search/text")
def search_text(q: str = Query(min_length=1, max_length=80),
                limit: int = Query(default=60, ge=1, le=100),
                session: Session = Depends(get_db)):
    """Merge exact title/taxonomy matches with model-backed photo similarities.

    No arbitrary category is fabricated from a picture. Semantic results are
    only returned if a real pretrained ML index is enabled and populated.
    """
    query = q.strip()
    if not query:
        return {'items': [], 'sellers': [], 'ml_enabled': SEARCH_BACKEND == 'clip'}
    query_leaves = precise_query_leaves(query)
    # Only one unambiguous primary type can exclude unrelated products.
    # Multi-type or broad queries remain inclusive.
    precise_type = query_leaves if len(query_leaves) == 1 else set()
    matched = session.scalars(product_query().where(
        text_filter(query)).order_by(Product.id).limit(limit * 3)).unique().all()
    ordered = [p for p in matched
               if not primary_type_conflicts(p, precise_type)][:limit]
    seen = {p.id for p in ordered}
    if SEARCH_BACKEND == 'clip' and len(ordered) < limit:
        # A neural model failure must not erase exact matches.
        import logging
        try:
            semantic_ids = visual_product_ids(session, query, limit=limit)
            if os.getenv('OPEN_VOCAB_SEARCH', '0') == '1':
                # Caption-based matching handles terms outside the fixed taxonomy.
                # Keep existing CLIP and exact-title matches as independent signals.
                try:
                    from .open_vocabulary import open_vocabulary_image_ids
                    caption_ids = open_vocabulary_image_ids(session, query, limit=limit)
                    semantic_ids = list(dict.fromkeys(semantic_ids + caption_ids))
                except Exception:
                    logging.getLogger(__name__).exception(
                        'Open-vocabulary search unavailable')
            if semantic_ids:
                extra = session.scalars(product_query().where(
                    Product.id.in_(semantic_ids)).where(
                    Product.id.not_in(seen))).unique().all()
                by_id = {p.id: p for p in extra}
                for pid in semantic_ids:
                    if (pid in by_id and pid not in seen
                            and not primary_type_conflicts(by_id[pid], precise_type)):
                        ordered.append(by_id[pid])
                        seen.add(pid)
                        if len(ordered) == limit:
                            break
        except Exception:
            logging.getLogger(__name__).exception(
                'Semantic text search unavailable for query')
    return {'items': [serialize_product(p) for p in ordered],
            'sellers': search_sellers(session, query),
            'ml_enabled': SEARCH_BACKEND == 'clip'}


@router.get("/products/{id}")
def product_detail(id: str, session: Session = Depends(get_db)):
    product = session.scalar(product_query().where(Product.id == id))
    if not product:
        raise HTTPException(status_code=404, detail="Товар не найден")
    return serialize_product(product)


@router.get("/sellers/{id}")
def seller_detail(id: str, session: Session = Depends(get_db)):
    seller = session.get(Seller, id)
    if not seller:
        raise HTTPException(status_code=404, detail="Продавец не найден")
    from .moderation_enforcement import shop_blocked
    if shop_blocked(session, id):
        raise HTTPException(status_code=404, detail="Продавец не найден")
    statement = product_query().join(Offer).where(Offer.seller_id == id).order_by(Product.id)
    products = session.scalars(statement).unique().all()
    from .merchant_models import PavilionClaim
    claims = session.scalars(select(PavilionClaim).where(PavilionClaim.seller_id == id)).all()
    pavilions = [{'id': c.pavilion_id, 'zone': session.get(Pavilion,c.pavilion_id).zone,
                  'code': session.get(Pavilion,c.pavilion_id).code} for c in claims]
    if not pavilions:
        pavilions = [{'id': seller.pavilion.id, 'zone': seller.pavilion.zone, 'code': seller.pavilion.code}]
    return {**serialize_seller(seller), 'pavilions': pavilions, "products": [serialize_product(p) for p in products]}


@router.get("/pavilions/{id}")
def pavilion_detail(id: str, session: Session = Depends(get_db)):
    pavilion = session.get(Pavilion, id)
    if pavilion is None:
        # Legacy callers pass seller ID instead of pavilion ID.
        seller = session.get(Seller, id)
        pavilion = seller.pavilion if seller else None
    if pavilion is None:
        raise HTTPException(status_code=404, detail="Павильон не найден")
    return {"id": pavilion.id, "code": pavilion.code, "zone": pavilion.zone, "demo": False}


_search_slots = BoundedSemaphore(2)


def reserve_search(request: Request, session: Session = Depends(get_db)):
    ip = request.client.host if request.client else 'unknown'
    rate_limit(session, 'photo-ip:' + digest(ip), 20, window=60)
    if not _search_slots.acquire(blocking=False):
        raise HTTPException(503, 'Фотопоиск занят. Повторите запрос.', headers={'Retry-After': '2'})
    try:
        yield
    finally:
        _search_slots.release()


@router.post("/search/image", dependencies=[Depends(reserve_search)], openapi_extra={
    'requestBody': {'required': True, 'content': {'multipart/form-data': {'schema': {
        'type': 'object', 'required': ['file'], 'properties': {
            'file': {'type': 'string', 'format': 'binary'}, 'crop': {'type': 'string'}}}}}}})
def search_image(photo: tuple[bytes, str] = Depends(read_search_photo),
                 limit: int = Query(default=12, ge=1, le=50),
                 category: str | None = None, min_score: float | None = Query(default=None, ge=-1, le=1),
                 session: Session = Depends(get_db)):
    content, crop = photo
    try:
        selected = crop_image(content, crop)
        # Products can have up to 12 images. Fetch enough candidates before
        # deduplicating by product; otherwise multiple angles of one listing
        # crowd other relevant products out of the top-12 results.
        candidate_count = max(128, min(600, 12 * limit))
        filter_category = category if category != 'Все' else None
        category_ids = category_ids_for_filter(filter_category)
        if SEARCH_BACKEND == 'clip':
            from .ml_index import nearest_ml_images
            nearest = nearest_ml_images(session, selected, limit=candidate_count,
                                        category=filter_category, category_ids=category_ids)
        else:
            nearest = nearest_images(session, selected, limit=candidate_count,
                                     category=filter_category, category_ids=category_ids)
    except SearchCapacityError as exc:
        raise HTTPException(503, str(exc), headers={'Retry-After': '3'}) from exc
    except InvalidImage as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    # Do not fill the results grid with unrelated nearest neighbours just
    # because the catalogue contains images. This cosine value is a tuning
    # floor, never a probability or a promise of a matching item.
    effective_min_score = (max(PHOTO_SEARCH_MIN_SCORE, min_score)
                           if min_score is not None else PHOTO_SEARCH_MIN_SCORE) if SEARCH_BACKEND == 'clip' else min_score
    active_model = MODEL_ID if SEARCH_BACKEND == 'classic' else CLIP_MODEL_ID
    active_method = 'visual_descriptor' if SEARCH_BACKEND == 'classic' else 'openclip_image_embedding'
    ids = [image_id for image_id, _ in nearest]
    image_product_ids = dict(session.execute(select(ProductImage.id, ProductImage.product_id)
                                             .where(ProductImage.id.in_(ids))).all())
    best_by_product = {}
    for image_id, score in nearest:
        product_id = image_product_ids.get(image_id)
        if product_id and (effective_min_score is None or score >= effective_min_score):
            best_by_product.setdefault(product_id, score)
        if len(best_by_product) == limit:
            break
    products = session.scalars(product_query().where(Product.id.in_(list(best_by_product)))).all()
    product_map = {p.id: p for p in products}
    return {
        "items": [{"product": serialize_product(product_map[pid]), "score": round(score, 6)}
                  for pid, score in list(best_by_product.items())[:limit] if pid in product_map],
        "demo": True, "model": active_model, "method": active_method,
        "crop_applied": bool(crop.strip()), "min_score": effective_min_score, "category": category,
        "notice": ("Нет товаров по выбранным условиям. Измените область, категорию или порог. " if not best_by_product else "") + ("Сходство рассчитано нейросетью OpenCLIP. Результат не является вероятностью и не подтверждает идентичность товара."
                   if SEARCH_BACKEND == 'clip' else
                   "Сходство рассчитано по цветам, композиции и контурам. Это не распознавание модели товара и не подтверждение идентичности."),
    }

@router.get("/products/{id}/share", response_class=HTMLResponse, include_in_schema=False)
def shared_product(id: str, session: Session = Depends(get_db)):
    """Public browser fallback; no private or withdrawn product data."""
    from html import escape
    from urllib.parse import quote
    product = session.scalar(product_query().where(Product.id == id))
    if product is None or not product.offers:
        return HTMLResponse('<!doctype html><html lang="ru"><meta charset="utf-8"><title>Садоход</title><p>Товар недоступен.</p></html>', status_code=404,
                            headers={'Cache-Control': 'no-store'})
    data = serialize_product(product)
    title = escape(data['title'] or 'Товар')
    description = escape(data['description'] or '')
    price = f"≈ {data['price']:,} ₽".replace(',', ' ') if data['price'] is not None else 'Цена по запросу'
    images = data['images']
    image = '/media/products/' + quote(images[0].rsplit('/', 1)[-1], safe='') if images else ''
    photo = f'<img src="{escape(image, quote=True)}" alt="{title}">' if image else ''
    page = f'''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — Садоход</title><meta property="og:title" content="{title} — Садоход">
<style>body{{font:16px system-ui,sans-serif;margin:24px auto;padding:0 20px;max-width:480px;color:#111}}img{{width:100%;max-height:65vh;object-fit:contain;border-radius:12px}}p{{white-space:pre-wrap;overflow-wrap:anywhere}}</style>
</head><body><main><header>Садоход</header>{photo}<h1>{title}</h1><strong>{price}</strong><p>{description}</p></main></body></html>'''
    return HTMLResponse(page, headers={'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        'Content-Security-Policy': "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"})
