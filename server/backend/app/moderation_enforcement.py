"""Server-side moderation restrictions shared by buyer, seller and offers.

Ban checks happen at authentication and at the final publication choke point.
No marketplace restriction is implemented solely in JavaScript.
"""
import time

from fastapi import HTTPException
from sqlalchemy import select

from .moderation_enforcement_models import AccountRestriction, ShopRestriction
from .merchant_models import MerchantListing, MerchantProduct, ShopMembership
from .models import Product, Seller


def active(row):
    return bool(row and row.active and (row.until is None or row.until > time.time()))


def account_blocked(db, buyer_id):
    return active(db.get(AccountRestriction, buyer_id))


def shop_blocked(db, seller_id):
    if active(db.get(ShopRestriction, seller_id)):
        return True
    owners = db.scalars(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == seller_id, ShopMembership.role == 'owner')).all()
    return any(account_blocked(db, bid) for bid in owners)


def require_account_allowed(db, buyer_id):
    if account_blocked(db, buyer_id):
        raise HTTPException(403, 'Аккаунт ограничен модерацией. Обратитесь в поддержку.')


def require_shop_allowed(db, seller_id):
    if shop_blocked(db, seller_id):
        raise HTTPException(403, 'Магазин ограничен модерацией. Обратитесь в поддержку.')
    owners = db.scalars(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == seller_id, ShopMembership.role == 'owner')).all()
    if any(account_blocked(db, bid) for bid in owners):
        raise HTTPException(403, 'Владелец магазина ограничен модерацией.')


def hide_shop_offers(db, seller_id):
    """Withdraw all live offers while holding the seller lock."""
    from .merchant_operations import drop_offer
    db.scalar(select(Seller).where(Seller.id == seller_id).with_for_update(of=Seller))
    for row in db.scalars(select(MerchantListing).where(
            MerchantListing.seller_id == seller_id)).all():
        if row.offer_id:
            drop_offer(db, row)
        if row.status == 'approved':
            row.status = 'paused'
    for owner in db.scalars(select(MerchantProduct).where(
            MerchantProduct.seller_id == seller_id)).all():
        product = db.get(Product, owner.product_id)
        if product and product.details:
            product.details.active = False
