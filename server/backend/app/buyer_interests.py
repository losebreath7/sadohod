"""Personalized home tags built from existing publishable catalog categories.

Only category-level daily counts are retained, not a browsing log.
Exploration is deterministic per week: tags do not jump on every refresh.
"""
import hashlib
import time
from collections import Counter, defaultdict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, delete
from sqlalchemy.orm import Session

from .account import Buyer, Favorite, current_buyer
from .buyer_interests_models import BuyerCategoryInterest
from .catalog_taxonomy import BY_ID, LEGACY, path_ids
from .database import get_db
from .merchant_models import ProductCategoryAssignment
from .models import Offer, Product, ProductDetails

router = APIRouter(prefix='/api/v1/account/interests', tags=['Buyer interests'])
WINDOW_DAYS = 30
MAX_DAILY_VIEWS = 12
DEFAULT_TAGS = ('clothing-trousers', 'clothing-outerwear', 'bags-hats',
                'clothing-tshirts', 'shoes')
# Only category IDs from the existing taxonomy, never fabricated suggestions.


class ViewEvent(BaseModel):
    product_id: str = Field(min_length=1, max_length=32)


def category_for(db: Session, product: Product):
    assigned = db.get(ProductCategoryAssignment, product.id)
    if assigned and assigned.category_id in BY_ID:
        return assigned.category_id
    return LEGACY.get(product.category)


def available_categories(db: Session):
    """Count visible products that actually have live offers."""
    products = db.scalars(select(Product).join(Offer).outerjoin(
        ProductDetails, ProductDetails.product_id == Product.id
    ).where((ProductDetails.active.is_(True)) | (ProductDetails.product_id.is_(None)))
     .distinct()).all()
    counts = Counter()
    for product in products:
        category = category_for(db, product)
        if category:
            for ancestor in path_ids(category):
                counts[ancestor] += 1
    return counts


def selected_tags(available, interest_scores, buyer_id, *, day):
    candidates = set(available)
    # Category names are not unique (e.g. several "Куртки").
    # A single tag name is shown once, and only for categories with inventory.
    used_names = set()
    result = []

    def append(category):
        if category not in candidates or len(result) >= 5:
            return False
        title = BY_ID[category][2]
        if title.casefold() in used_names:
            return False
        result.append({'id': category, 'name': title})
        used_names.add(title.casefold())
        return True

    scored = sorted(candidates, key=lambda c: (-interest_scores.get(c, 0), -available[c], c))
    personally_scored = [c for c in scored if interest_scores.get(c, 0) > 0]
    if personally_scored:
        for category in personally_scored:
            if len(result) >= 3:
                break
            append(category)
        # One adjacent category; same taxonomy parent/ancestor, not arbitrary
        # unrelated products. Parent/child categories count as related too.
        anchors = list(result)
        related = [c for c in scored if c not in {x['id'] for x in result}
                   and any(set(path_ids(c)) & set(path_ids(a['id'])) for a in anchors)]
        for category in related:
            if append(category):
                break
        # One exploration slot, rotate every seven days and avoid repeating
        # the same category against current personal picks.
        unknown = [c for c in sorted(candidates) if c not in {x['id'] for x in result}
                   and interest_scores.get(c, 0) <= 0]
        if unknown and len(result) < 5:
            seed = hashlib.sha256(f'{buyer_id}:{day // 7}'.encode()).digest()
            start = int.from_bytes(seed[:8], 'big') % len(unknown)
            for index in range(len(unknown)):
                if append(unknown[(start + index) % len(unknown)]):
                    break
    else:
        for c in DEFAULT_TAGS:
            append(c)
    for category in scored:
        append(category)
        if len(result) >= 5:
            break
    return result


@router.post('/view')
def record_view(body: ViewEvent, buyer: Buyer = Depends(current_buyer),
                db: Session = Depends(get_db)):
    # No external tracking, only authenticated actions and public listings.
    product = db.get(Product, body.product_id)
    if not product or not db.scalar(select(Offer.id).where(
            Offer.product_id == body.product_id).limit(1)):
        raise HTTPException(404, 'Товар недоступен')
    if product.details is not None and not product.details.active:
        raise HTTPException(404, 'Товар недоступен')
    category = category_for(db, product)
    if not category:
        return {'tracked': False}
    now = time.time()
    day = int(now // 86400)
    record = db.get(BuyerCategoryInterest, (buyer.id, category, day))
    if record is None:
        record = BuyerCategoryInterest(buyer_id=buyer.id, category_id=category,
                                       day=day, views=0, updated_at=now)
        db.add(record)
    record.views = min(MAX_DAILY_VIEWS, record.views + 1)
    record.updated_at = now
    # Old rows are no longer needed; do not keep user browsing data indefinitely.
    db.execute(delete(BuyerCategoryInterest).where(
        BuyerCategoryInterest.buyer_id == buyer.id,
        BuyerCategoryInterest.day < day - WINDOW_DAYS))
    db.commit()
    return {'tracked': True}


@router.get('/tags')
def tags(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    now_day = int(time.time() // 86400)
    available = available_categories(db)
    scores = defaultdict(float)
    # Global TTL pruning also runs on reads, including users who never browse again.
    db.execute(delete(BuyerCategoryInterest).where(
        BuyerCategoryInterest.day < now_day - WINDOW_DAYS))
    db.commit()
    records = db.scalars(select(BuyerCategoryInterest).where(
        BuyerCategoryInterest.buyer_id == buyer.id,
        BuyerCategoryInterest.day >= now_day - WINDOW_DAYS)).all()
    for item in records:
        if item.category_id not in BY_ID:
            continue
        age = max(0, now_day - item.day)
        weight = max(0.10, 1 - age / 36)
        for category in path_ids(item.category_id):
            scores[category] += item.views * weight
    favorite_ids = db.scalars(select(Favorite.item).where(
        Favorite.buyer == buyer.id, Favorite.kind == 'product')).all()
    if favorite_ids:
        products = db.scalars(select(Product).where(Product.id.in_(favorite_ids))).all()
        for product in products:
            category = category_for(db, product)
            if category and category in available:
                for ancestor in path_ids(category):
                    scores[ancestor] += 5
    return {'items': selected_tags(available, scores, buyer.id, day=now_day)}
