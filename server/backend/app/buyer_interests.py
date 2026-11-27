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
from .catalog_taxonomy import BY_ID, LEGACY, path_ids, resolve_leaf
from .text_search import matched_category_ids
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
    engaged: bool = False


class SearchEvent(BaseModel):
    query: str = Field(min_length=1, max_length=80)


def category_for(db: Session, product: Product):
    """Use a proven leaf from the title when old taxonomy is only generic."""
    assigned = db.get(ProductCategoryAssignment, product.id)
    category = assigned.category_id if assigned and assigned.category_id in BY_ID else LEGACY.get(product.category)
    leaf = resolve_leaf(product.title)
    if leaf and (not category or category in path_ids(leaf)):
        return leaf
    return category


def available_categories(db: Session):
    """Count visible products that actually have live offers."""
    from .api import visible_products
    products = db.scalars(select(Product).join(Offer).where(visible_products())
                          .distinct()).all()
    counts = Counter()
    for product in products:
        category = category_for(db, product)
        if category:
            for ancestor in path_ids(category):
                counts[ancestor] += 1
    return counts


def selected_tags(available, interest_scores, buyer_id, *, day, direct_scores=None):
    """Three personal tags, one related category, one rotating discovery."""
    candidates = set(available)
    direct_scores = direct_scores or {}
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

    def rank(category):
        # A specifically searched/viewed skirt beats broad 'Clothing'
        # even when parent categories aggregate more generic interactions.
        specificity = len(path_ids(category))
        return (-direct_scores.get(category, 0), -interest_scores.get(category, 0),
                -specificity, -available[category], category)

    scored = sorted(candidates, key=rank)
    personal = [c for c in scored if direct_scores.get(c, 0) > 0]
    if not personal:
        personal = [c for c in scored if interest_scores.get(c, 0) > 0]

    if personal:
        for category in personal:
            if len(result) >= 3:
                break
            append(category)

        anchors = [row['id'] for row in result]
        # Prefer another leaf in the same subtree over its generic parent.
        related = sorted((c for c in candidates if c not in anchors and
            any(set(path_ids(c)) & set(path_ids(anchor)) for anchor in anchors)),
            key=lambda c: (-len(path_ids(c)), -available[c], c))
        for category in related:
            if append(category):
                break

        unknown = [c for c in sorted(candidates) if
                   direct_scores.get(c, 0) == 0 and interest_scores.get(c, 0) == 0]
        if unknown and len(result) < 5:
            seed = hashlib.sha256(f'{buyer_id}:{day // 7}'.encode()).digest()
            start = int.from_bytes(seed[:8], 'big') % len(unknown)
            for index in range(len(unknown)):
                if append(unknown[(start + index) % len(unknown)]):
                    break
    else:
        for category in DEFAULT_TAGS:
            append(category)
    for category in scored:
        append(category)
        if len(result) == 5:
            break
    return result


def add_interest(db, buyer_id, category_id, increment):
    if category_id not in BY_ID:
        return
    now = time.time()
    day = int(now // 86400)
    record = db.get(BuyerCategoryInterest, (buyer_id, category_id, day))
    if record is None:
        record = BuyerCategoryInterest(buyer_id=buyer_id, category_id=category_id,
                                       day=day, views=0, updated_at=now)
        db.add(record)
    record.views = min(MAX_DAILY_VIEWS, record.views + increment)
    record.updated_at = now
    db.execute(delete(BuyerCategoryInterest).where(
        BuyerCategoryInterest.buyer_id == buyer_id,
        BuyerCategoryInterest.day < day - WINDOW_DAYS))
    db.commit()


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
    from .feed import record_product_view
    record_product_view(db, buyer.id, product.id, body.engaged)
    category = category_for(db, product)
    if not category:
        db.commit()
        return {'tracked': False}
    add_interest(db, buyer.id, category, 2 if body.engaged else 1)
    return {'tracked': True}


@router.post('/search')
def record_search(body: SearchEvent, buyer: Buyer = Depends(current_buyer),
                  db: Session = Depends(get_db)):
    query = body.query.strip()
    matches = matched_category_ids(query)
    if not matches:
        return {'tracked': False}
    available = available_categories(db)
    eligible = [category for category in matches if category in available]
    if not eligible:
        return {'tracked': False}
    # matched_category_ids includes descendants. For broad queries such as
    # 'обувь' count the category asked for, not an arbitrary deepest child.
    # 'юбки' matches a leaf and therefore stays specific.
    category = min(eligible, key=lambda value: (len(path_ids(value)), -available[value], value))
    add_interest(db, buyer.id, category, 3)
    return {'tracked': True}


@router.get('/tags')
def tags(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    now_day = int(time.time() // 86400)
    available = available_categories(db)
    scores = defaultdict(float)
    direct = defaultdict(float)
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
        direct[item.category_id] += item.views * weight
        for category in path_ids(item.category_id):
            scores[category] += item.views * weight
    favorite_ids = db.scalars(select(Favorite.item).where(
        Favorite.buyer == buyer.id, Favorite.kind == 'product')).all()
    if favorite_ids:
        products = db.scalars(select(Product).where(Product.id.in_(favorite_ids))).all()
        for product in products:
            category = category_for(db, product)
            if category and category in available:
                direct[category] += 5
                for ancestor in path_ids(category):
                    scores[ancestor] += 5
    return {'items': selected_tags(available, scores, buyer.id, day=now_day, direct_scores=direct)}
