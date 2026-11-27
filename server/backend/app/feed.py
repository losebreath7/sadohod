"""Hybrid buyer recommendations. Search endpoints remain independent.

Rank lightweight metadata once per bounded, account-scoped browsing snapshot.
Only hydrate requested products; re-check publication/moderation for every page.
No synthetic views or ratings. Older publications without a timestamp stay neutral.
"""
from collections import Counter, OrderedDict, defaultdict, deque
from dataclasses import dataclass
import hashlib
import math
import secrets
import threading
import time

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from .account import Favorite, current_buyer
from .api import product_query, serialize_product, visible_products, product_category_filter
from .buyer_interests_models import BuyerCategoryInterest
from .buyer_reviews_v082 import SellerReview
from .catalog_taxonomy import BY_ID, LEGACY, path_ids, resolve_leaf
from .database import get_db
from .feed_config import (WEIGHTS, ALGORITHM, PAGE_SIZE, WINDOW_DAYS, FRESH_DAYS,
                          SNAPSHOT_TTL, SNAPSHOT_LIMIT, SELLER_CAP, CATEGORY_CAP)
from .feed_models import FeedPublication, FeedView
from .merchant_models import MerchantProduct, ProductCategoryAssignment, ShopMembership
from .models import Offer, Product, ProductImage
from .moderation_enforcement_models import AccountRestriction, ShopRestriction
from .product_safety import ProductSafetyHold

router = APIRouter(prefix='/api/v1', tags=['Buyer feed'])


def _insert(db, model):
    if db.get_bind().dialect.name == 'postgresql':
        from sqlalchemy.dialects.postgresql import insert
    else:
        from sqlalchemy.dialects.sqlite import insert
    return insert(model)


def record_publication(db, product_id):
    # A pause/resume, move or price edit does not renew freshness.
    stmt = _insert(db, FeedPublication).values(product_id=product_id, published_at=time.time())
    db.execute(stmt.on_conflict_do_nothing(index_elements=['product_id']))


def record_product_view(db, buyer_id, product_id, engaged):
    # At most one view per account/product/day, with one engagement upgrade.
    own = select(Offer.id).join(ShopMembership, ShopMembership.seller_id == Offer.seller_id).where(
        Offer.product_id == product_id, ShopMembership.buyer_id == buyer_id)
    if db.scalar(own.limit(1)):
        return
    day = int(time.time() // 86400)
    stmt = _insert(db, FeedView).values(buyer_id=buyer_id, product_id=product_id,
                                       day=day, engaged=engaged)
    db.execute(stmt.on_conflict_do_update(
        index_elements=['buyer_id', 'product_id', 'day'],
        set_={'engaged': or_(FeedView.engaged, stmt.excluded.engaged)}))
    db.execute(delete(FeedView).where(FeedView.day < day - WINDOW_DAYS))


def public_conditions(now):
    blocked = select(ShopRestriction.seller_id).where(
        ShopRestriction.active.is_(True),
        or_(ShopRestriction.until.is_(None), ShopRestriction.until > now))
    owners = select(ShopMembership.seller_id).join(
        AccountRestriction, AccountRestriction.buyer_id == ShopMembership.buyer_id).where(
        ShopMembership.role == 'owner', AccountRestriction.active.is_(True),
        or_(AccountRestriction.until.is_(None), AccountRestriction.until > now))
    unavailable = select(Offer.product_id).where(
        or_(Offer.seller_id.in_(blocked), Offer.seller_id.in_(owners)))
    return (
        visible_products(),
        Product.id.in_(select(Offer.product_id)),
        Product.id.not_in(unavailable),
        Product.id.not_in(select(ProductSafetyHold.product_id).where(ProductSafetyHold.active.is_(True))),
        Product.id.not_in(select(MerchantProduct.product_id).where(MerchantProduct.status != 'approved')),
    )


def _category(title, legacy, assigned):
    category = assigned if assigned in BY_ID else LEGACY.get(legacy)
    leaf = resolve_leaf(title)
    return leaf if leaf and (not category or category in path_ids(leaf)) else category


def _interest(db, buyer_id, day):
    direct = defaultdict(float)
    shops = set()
    if not buyer_id:
        return direct, shops
    for category, date, count in db.execute(select(
            BuyerCategoryInterest.category_id, BuyerCategoryInterest.day, BuyerCategoryInterest.views
        ).where(BuyerCategoryInterest.buyer_id == buyer_id, BuyerCategoryInterest.day >= day - WINDOW_DAYS)):
        if category in BY_ID:
            direct[category] += count * max(.1, 1 - max(0, day-date)/36)
    for title, legacy, assigned in db.execute(select(Product.title, Product.category,
            ProductCategoryAssignment.category_id).outerjoin(ProductCategoryAssignment,
            ProductCategoryAssignment.product_id == Product.id).join(Favorite,
            (Favorite.item == Product.id) & (Favorite.kind == 'product')).where(Favorite.buyer == buyer_id, *public_conditions(time.time()))):
        category = _category(title, legacy, assigned)
        if category:
            direct[category] += 5
    shops.update(db.scalars(select(Favorite.item).where(Favorite.buyer == buyer_id, Favorite.kind == 'seller')))
    return direct, shops


def affinity(category, direct):
    if not category or not direct:
        return 0.
    path = path_ids(category)
    maximum = max(direct.values(), default=1)
    values = []
    for interested, weight in direct.items():
        other = path_ids(interested)
        if category == interested:
            relation = 1.
        elif interested in path:
            relation = .80
        elif category in other:
            relation = .45
        elif path and other and path[0] == other[0]:
            relation = .15
        else:
            relation = 0.
        values.append(relation * min(1., weight / max(1., maximum)))
    return max(values, default=0.)


@dataclass(frozen=True)
class Candidate:
    id: str
    seller: str
    category: str
    interest: float
    popularity: float
    freshness: float
    quality: float
    seller_rating: float
    exploration: float

    @property
    def score(self):
        return sum(WEIGHTS[key] * getattr(self, key) for key in WEIGHTS)


def _stable(seed, value):
    return int.from_bytes(hashlib.blake2b(f'{seed}:{value}'.encode(), digest_size=8).digest(), 'big')


def rank(candidates, seed):
    """Bounded-lookahead diversification; never drop products or duplicate IDs."""
    items = {c.id: c for c in candidates}
    ordered = sorted(items.values(), key=lambda c: (-c.score, _stable(seed, c.id), c.id))
    lanes = {
        'main': deque(ordered),
        'personal': deque(c for c in ordered if c.interest >= .45),
        'new': deque(c for c in ordered if c.freshness >= .5),
        'popular': deque(c for c in ordered if c.popularity > 0),
        'explore': deque(c for c in ordered if c.interest < .15),
    }
    pattern = ['personal','personal','new','personal','popular','personal','explore','personal','new','personal',
               'personal','new','personal','popular','personal','explore','personal','new','personal','personal']
    chosen = set()
    result = []
    sellers, categories = Counter(), Counter()

    def pick(lane, capped=True):
        queue = lanes[lane]
        skipped = []
        found = None
        # Looking beyond the first score alone protects smaller shops.
        while queue and len(skipped) < 256:
            c = queue.popleft()
            if c.id in chosen:
                continue
            if not capped or (sellers[c.seller] < SELLER_CAP and categories[c.category] < CATEGORY_CAP):
                found = c
                break
            skipped.append(c)
        queue.extendleft(reversed(skipped))
        return found

    while len(result) < len(items):
        index = len(result) % PAGE_SIZE
        if index == 0:
            sellers.clear()
            categories.clear()
        c = pick(pattern[index]) or pick('main') or pick('main', capped=False)
        if c is None:
            break
        chosen.add(c.id)
        result.append(c.id)
        sellers[c.seller] += 1
        categories[c.category] += 1
    return result


def candidates(db, buyer_id, category_filter, now):
    day = int(now // 86400)
    direct, shops = _interest(db, buyer_id, day)
    # Count distinct accounts, not clicks. Owner's views are not recorded.
    views = dict(db.execute(select(FeedView.product_id, func.count(func.distinct(FeedView.buyer_id)))
                           .where(FeedView.day >= day - WINDOW_DAYS).group_by(FeedView.product_id)).all())
    engaged = dict(db.execute(select(FeedView.product_id, func.count(func.distinct(FeedView.buyer_id)))
                             .where(FeedView.day >= day - WINDOW_DAYS, FeedView.engaged.is_(True))
                             .group_by(FeedView.product_id)).all())
    favorites = dict(db.execute(select(Favorite.item, func.count(func.distinct(Favorite.buyer)))
                   .where(Favorite.kind == 'product').group_by(Favorite.item)).all())
    reviews = {sid:(count, avg) for sid,count,avg in db.execute(
        select(SellerReview.seller, func.count(SellerReview.id), func.avg(SellerReview.rating))
        .where(SellerReview.hidden.is_(False), SellerReview.moderation_status == 'approved')
        .group_by(SellerReview.seller))}
    photos = select(ProductImage.product_id.label('pid'), func.count(ProductImage.id).label('n')).group_by(
        ProductImage.product_id).subquery()
    offers = select(Offer.product_id.label('pid'), func.min(Offer.seller_id).label('seller'),
                    func.min(Offer.price).label('price')).group_by(Offer.product_id).subquery()
    stmt = (select(Product.id, Product.title, Product.category, Product.description,
                    ProductCategoryAssignment.category_id, offers.c.seller, offers.c.price,
                    photos.c.n, FeedPublication.published_at)
            .join(offers, offers.c.pid == Product.id)
            .outerjoin(photos, photos.c.pid == Product.id)
            .outerjoin(ProductCategoryAssignment, ProductCategoryAssignment.product_id == Product.id)
            .outerjoin(FeedPublication, FeedPublication.product_id == Product.id)
            .where(*public_conditions(now)))
    if category_filter and category_filter != 'Все':
        stmt = stmt.where(product_category_filter(category_filter))
    for pid,title,legacy,description,assigned,seller,price,photo_count,published in db.execute(stmt):
        category = _category(title, legacy, assigned)
        personal = max(affinity(category,direct), .75 if seller in shops else 0.)
        # Log saturation avoids a few viral listings overwhelming the catalogue.
        popular = min(1., math.log1p(views.get(pid,0) + 2*engaged.get(pid,0) + 4*favorites.get(pid,0))/math.log1p(100))
        fresh = math.exp(-max(0., now-published)/(FRESH_DAYS*86400)) if published is not None else 0.
        # Price/title are optional; do not require them to be present.
        quality = min(1., .7 * min(1., (photo_count or 0)/2) +
                      .15 * bool(title and title != 'Без названия') + .15 * bool(description and description.strip()))
        count, avg = reviews.get(seller, (0, 3.5))
        rating = (float(avg)*count + 3.5*5)/(count+5)/5
        explore = (1-personal) * (_stable(str(day), pid)/2**64)
        yield Candidate(pid,seller,category or legacy or 'unknown',personal,popular,fresh,quality,rating,explore)


@dataclass
class Snapshot:
    owner: str
    category: str
    expires: float
    ids: list[str]


_snapshots = OrderedDict()
_lock = threading.Lock()


def _snapshot(db, owner, buyer_id, category, now):
    ids = rank(list(candidates(db, buyer_id, category, now)), f'{owner}:{int(now//86400)}')
    key = secrets.token_urlsafe(24)
    snap = Snapshot(owner, category, now+SNAPSHOT_TTL, ids)
    with _lock:
        for stale in [k for k,v in _snapshots.items() if v.expires <= now]:
            _snapshots.pop(stale,None)
        _snapshots[key] = snap
        while len(_snapshots) > SNAPSHOT_LIMIT:
            _snapshots.popitem(last=False)
    return key,snap


@router.get('/feed')
def feed(response: Response, authorization: str = Header(default=''),
         cursor: str | None = Query(default=None, max_length=120),
         category: str = Query(default='Все', max_length=100),
         db: Session = Depends(get_db)):
    response.headers['Cache-Control'] = 'private, no-store'
    buyer = current_buyer(authorization,db) if authorization else None
    owner = buyer.id if buyer else 'guest'
    now = time.time()
    if cursor:
        try:
            key, raw = cursor.rsplit('.',1)
            offset = int(raw)
        except ValueError:
            raise HTTPException(400,'Некорректная страница') from None
        with _lock:
            snap = _snapshots.get(key)
        if not snap or snap.expires <= now or snap.owner != owner or snap.category != category:
            raise HTTPException(410,'Лента устарела. Обновите главную страницу.')
        if offset < 0 or offset > len(snap.ids):
            raise HTTPException(400,'Некорректная страница')
    else:
        key,snap = _snapshot(db,owner,buyer.id if buyer else None,category,now)
        offset = 0
    items = []
    # Skip products withdrawn since ranking; keep the original order for the rest.
    while offset < len(snap.ids) and len(items) < PAGE_SIZE:
        ids = snap.ids[offset:offset+PAGE_SIZE-len(items)]
        products = {p.id:p for p in db.scalars(product_query().where(
            Product.id.in_(ids), *public_conditions(now))).unique().all()}
        items.extend(serialize_product(products[pid]) for pid in ids if pid in products)
        offset += len(ids)
    return {'items':items, 'next_cursor':f'{key}.{offset}' if offset < len(snap.ids) else None,
            'algorithm':ALGORITHM}
