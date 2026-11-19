"""Proactive moderation of any existing account, shop, product or review.

A report is not required. All mutations require staff auth, a reason and are
audited in the same transaction as persistent restriction/email receipts.
"""
import secrets
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from .account import Buyer, BuyerSession, LoginCode
from .buyer_reviews_v082 import SellerReview
from .database import get_db
from .merchant_models import MerchantProduct, MerchantListing, ShopMembership
from .models import Product, Seller
from .moderation import require_moderator, record_action
from .moderation_models import ModeratorUser
from .moderation_enforcement_models import AccountRestriction, ShopRestriction
from .moderation_enforcement import active, hide_shop_offers, require_shop_allowed, account_blocked
from .moderation_email import queue_decision
from .product_safety import ProductSafetyHold, take_down

router = APIRouter(prefix='/api/v1/moderation/control', tags=['Moderation control'])


class Action(BaseModel):
    action: Literal['block', 'unblock', 'hide', 'restore']
    reason: str = Field(min_length=5, max_length=500)
    # Null means indefinite restriction, otherwise Unix expiration.
    until: float | None = Field(default=None, gt=0)


def seller_owner(db, seller_id):
    buyer_id = db.scalar(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == seller_id,
        ShopMembership.role == 'owner'))
    return db.get(Buyer, buyer_id) if buyer_id else None


def email_for_product(db, pid):
    row = db.get(MerchantProduct, pid)
    return seller_owner(db, row.seller_id) if row else None


@router.get('/search')
def search(kind: Literal['accounts', 'shops', 'products', 'reviews'],
           q: str = Query(default='', max_length=160),
           staff: ModeratorUser = Depends(require_moderator),
           db: Session = Depends(get_db)):
    term = q.strip()
    if kind == 'accounts':
        stmt = select(Buyer).order_by(Buyer.id.desc())
        if term:
            stmt = stmt.where(or_(Buyer.id == term, Buyer.email.ilike(f'%{_escape(term)}%', escape='\\'),
                                  Buyer.name.ilike(f'%{_escape(term)}%', escape='\\')))
        rows = db.scalars(stmt.limit(100)).all()
        return {'items': [{
            'id': x.id, 'title': x.email, 'subtitle': x.name,
            'blocked': active(db.get(AccountRestriction, x.id)),
            'reason': (db.get(AccountRestriction, x.id).reason
                       if db.get(AccountRestriction, x.id) else '')
        } for x in rows]}
    if kind == 'shops':
        stmt = select(Seller).order_by(Seller.id.desc())
        if term:
            stmt = stmt.where(or_(Seller.id == term, Seller.name.ilike(
                f'%{_escape(term)}%', escape='\\')))
        rows = db.scalars(stmt.limit(100)).all()
        return {'items': [{
            'id': x.id, 'title': x.name,
            'subtitle': (seller_owner(db, x.id).email
                         if seller_owner(db, x.id) else ''),
            'blocked': active(db.get(ShopRestriction, x.id)),
            'reason': (db.get(ShopRestriction, x.id).reason
                       if db.get(ShopRestriction, x.id) else '')
        } for x in rows]}
    if kind == 'products':
        stmt = select(Product).order_by(Product.id.desc())
        if term:
            stmt = stmt.where(or_(Product.id == term,
                                  Product.title.ilike(f'%{_escape(term)}%', escape='\\')))
        rows = db.scalars(stmt.limit(100)).all()
        return {'items': [{
            'id': x.id, 'title': x.title, 'subtitle': x.category,
            'images': [f'/media/products/{im.filename}' for im in x.images[:6]],
            'blocked': bool(db.get(ProductSafetyHold, x.id) and
                            db.get(ProductSafetyHold, x.id).active),
            'reason': (db.get(ProductSafetyHold, x.id).reason
                       if db.get(ProductSafetyHold, x.id) else '')
        } for x in rows]}
    stmt = select(SellerReview).order_by(SellerReview.created_at.desc())
    if term:
        stmt = stmt.where(or_(SellerReview.id == term,
                              SellerReview.text.ilike(f'%{_escape(term)}%', escape='\\')))
    rows = db.scalars(stmt.limit(100)).all()
    return {'items': [{
        'id': x.id, 'title': x.text[:150] or 'Отзыв без текста',
        'subtitle': f'Оценка {x.rating}/5 · Магазин {x.seller}',
        'blocked': x.hidden, 'reason': ''
    } for x in rows]}


def _escape(value):
    return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')


@router.post('/{kind}/{item_id}')
def decide(kind: Literal['accounts', 'shops', 'products', 'reviews'],
           item_id: str, body: Action,
           staff: ModeratorUser = Depends(require_moderator),
           db: Session = Depends(get_db)):
    reason = body.reason.strip()
    if len(reason) < 5:
        raise HTTPException(422, 'Причина должна содержать минимум 5 символов')
    if kind in ('accounts', 'shops'):
        if body.action not in ('block', 'unblock'):
            raise HTTPException(422, 'Недопустимое действие')
        if body.action == 'block' and body.until is not None and body.until <= time.time():
            raise HTTPException(422, 'Дата окончания блокировки должна быть в будущем')
    else:
        if body.action not in ('hide', 'restore'):
            raise HTTPException(422, 'Недопустимое действие')
        if body.until is not None:
            raise HTTPException(422, 'Срок доступен только для блокировки аккаунта/магазина')

    if kind == 'accounts':
        buyer = db.get(Buyer, item_id)
        if buyer is None:
            raise HTTPException(404, 'Аккаунт не найден')
        db.scalar(select(Buyer).where(Buyer.id == buyer.id).with_for_update())
        restriction = db.get(AccountRestriction, item_id)
        was_active = active(restriction)
        if was_active == (body.action == 'block'):
            raise HTTPException(409, 'Ограничение уже в указанном состоянии')
        if restriction is None:
            restriction = AccountRestriction(buyer_id=item_id, moderator_id=staff.id)
            db.add(restriction)
        restriction.active = body.action == 'block'
        restriction.reason = reason
        restriction.until = body.until if restriction.active else None
        restriction.moderator_id = staff.id
        restriction.updated_at = time.time()
        if restriction.active:
            db.execute(delete(BuyerSession).where(BuyerSession.buyer == item_id))
            db.execute(delete(LoginCode).where(LoginCode.email == buyer.email))
            for seller_id in db.scalars(select(ShopMembership.seller_id).where(
                    ShopMembership.buyer_id == item_id,
                    ShopMembership.role == 'owner')).all():
                hide_shop_offers(db, seller_id)
        recipient = buyer.email
        label = buyer.email
    elif kind == 'shops':
        shop = db.get(Seller, item_id)
        if shop is None:
            raise HTTPException(404, 'Магазин не найден')
        db.scalar(select(Seller).where(Seller.id == item_id).with_for_update(of=Seller))
        restriction = db.get(ShopRestriction, item_id)
        was_active = active(restriction)
        if was_active == (body.action == 'block'):
            raise HTTPException(409, 'Ограничение уже в указанном состоянии')
        if restriction is None:
            restriction = ShopRestriction(seller_id=item_id, moderator_id=staff.id)
            db.add(restriction)
        restriction.active = body.action == 'block'
        restriction.reason = reason
        restriction.until = body.until if restriction.active else None
        restriction.moderator_id = staff.id
        restriction.updated_at = time.time()
        if restriction.active:
            hide_shop_offers(db, item_id)
        owner = seller_owner(db, item_id)
        recipient = owner.email if owner else ''
        label = shop.name
    elif kind == 'products':
        product = db.get(Product, item_id)
        if product is None:
            raise HTTPException(404, 'Товар не найден')
        owner = db.get(MerchantProduct, item_id)
        if owner:
            db.scalar(select(Seller).where(Seller.id == owner.seller_id).with_for_update(of=Seller))
        hold = db.get(ProductSafetyHold, item_id)
        is_blocked = bool(hold and hold.active)
        if is_blocked == (body.action == 'hide'):
            raise HTTPException(409, 'Товар уже в указанном состоянии')
        if body.action == 'hide':
            take_down(db, item_id, staff.id, reason)
        else:
            if hold is None:
                raise HTTPException(409, 'Товар не был заблокирован')
            if owner:
                require_shop_allowed(db, owner.seller_id)
            hold.active = False
            hold.reason = reason
            hold.updated_at = time.time()
            # No automatic republishing: seller must explicitly resume, and
            # all normal publication guards still apply.
        recipient_buyer = email_for_product(db, item_id)
        recipient = recipient_buyer.email if recipient_buyer else ''
        label = product.title
    else:
        review = db.get(SellerReview, item_id, with_for_update=True)
        if review is None:
            raise HTTPException(404, 'Отзыв не найден')
        if review.hidden == (body.action == 'hide'):
            raise HTTPException(409, 'Отзыв уже в указанном состоянии')
        review.hidden = body.action == 'hide'
        author = db.get(Buyer, review.buyer)
        recipient = author.email if author else ''
        label = 'Отзыв о магазине'
    word = 'заблокирован' if body.action in ('hide', 'block') else 'восстановлен'
    record_action(db, staff, kind, item_id, body.action, reason)
    queue_decision(db, recipient, f'Объект {word}', kind, label, reason)
    db.commit()
    return {'id': item_id, 'kind': kind, 'action': body.action,
            'notification': 'queued' if recipient else 'no_email'}
