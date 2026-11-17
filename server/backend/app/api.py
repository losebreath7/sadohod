from threading import BoundedSemaphore

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select, or_
from sqlalchemy.orm import Session, selectinload

from .config import MODEL_ID, SEARCH_BACKEND
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
        statement = statement.where(Product.title.ilike(f"%{q.strip()[:80]}%"))
    items = session.scalars(statement.offset(offset).limit(limit)).all()
    return {"items": [serialize_product(p) for p in items], "limit": limit, "offset": offset, "demo": True}


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
        candidate_count = max(48, 4 * limit)
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
    active_model = MODEL_ID if SEARCH_BACKEND == 'classic' else CLIP_MODEL_ID
    active_method = 'visual_descriptor' if SEARCH_BACKEND == 'classic' else 'openclip_image_embedding'
    ids = [image_id for image_id, _ in nearest]
    image_product_ids = dict(session.execute(select(ProductImage.id, ProductImage.product_id)
                                             .where(ProductImage.id.in_(ids))).all())
    best_by_product = {}
    for image_id, score in nearest:
        product_id = image_product_ids.get(image_id)
        if product_id and (min_score is None or score >= min_score):
            best_by_product.setdefault(product_id, score)
        if len(best_by_product) == limit:
            break
    products = session.scalars(product_query().where(Product.id.in_(list(best_by_product)))).all()
    product_map = {p.id: p for p in products}
    return {
        "items": [{"product": serialize_product(product_map[pid]), "score": round(score, 6)}
                  for pid, score in list(best_by_product.items())[:limit] if pid in product_map],
        "demo": True, "model": active_model, "method": active_method,
        "crop_applied": bool(crop.strip()), "min_score": min_score, "category": category,
        "notice": ("Нет товаров по выбранным условиям. Измените область, категорию или порог. " if not best_by_product else "") + ("Сходство рассчитано нейросетью OpenCLIP. Результат не является вероятностью и не подтверждает идентичность товара."
                   if SEARCH_BACKEND == 'clip' else
                   "Сходство рассчитано по цветам, композиции и контурам. Это не распознавание модели товара и не подтверждение идентичности."),
    }
