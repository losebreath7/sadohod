"""Persistent enforcement for published products.

A staff takedown is separate from sellers' own pause/resume workflow. It must
survive product edits, uploads, save retries and pavilion moves.
"""
import time
import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Float, ForeignKey, String, Text, UniqueConstraint, select
from sqlalchemy.orm import Mapped, mapped_column, Session

from .account import Buyer, current_buyer, rate_limit
from .database import Base, get_db
from .models import Product, ProductDetails, Offer
from .merchant_models import MerchantProduct, MerchantListing, ShopMembership
from .seller_notifications import SellerNotification

router = APIRouter(prefix='/api/v1', tags=['Product safety'])


class ProductReport(Base):
    __tablename__ = 'product_reports'
    __table_args__ = (UniqueConstraint('buyer_id', 'product_id',
                                      name='uq_product_report_buyer_product'),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer_id: Mapped[str] = mapped_column(
        ForeignKey('buyers.id', ondelete='CASCADE'), index=True, nullable=False)
    product_id: Mapped[str] = mapped_column(
        ForeignKey('products.id', ondelete='CASCADE'), index=True, nullable=False)
    reason: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
    resolved_at: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    resolution: Mapped[str] = mapped_column(String(16), default='', nullable=False)


class ProductSafetyHold(Base):
    __tablename__ = 'product_safety_holds'
    product_id: Mapped[str] = mapped_column(
        ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    reason: Mapped[str] = mapped_column(Text, default='', nullable=False)
    moderator_id: Mapped[str] = mapped_column(
        ForeignKey('moderator_users.id'), nullable=False)
    updated_at: Mapped[float] = mapped_column(Float, nullable=False)


class ProductReportInput(BaseModel):
    reason: str = Field(min_length=4, max_length=200)


def is_held(db: Session, product_id: str) -> bool:
    hold = db.get(ProductSafetyHold, product_id)
    return bool(hold and hold.active)


def require_publishable(db: Session, product_id: str) -> None:
    if is_held(db, product_id):
        raise HTTPException(409, 'Товар снят с публикации модератором. Обратитесь в поддержку.')


@router.post('/products/{product_id}/report', status_code=201)
def report_product(product_id: str, body: ProductReportInput,
                   buyer: Buyer = Depends(current_buyer),
                   db: Session = Depends(get_db)):
    product = db.get(Product, product_id)
    if product is None or (product.details is not None and not product.details.active):
        raise HTTPException(404, 'Товар не найден')
    if db.scalar(select(Offer.id).where(Offer.product_id == product_id)) is None:
        raise HTTPException(404, 'Товар не найден')
    existing = db.scalar(select(ProductReport).where(
        ProductReport.buyer_id == buyer.id,
        ProductReport.product_id == product_id))
    if existing:
        return {'saved': True}
    if len(body.reason.strip()) < 4:
        raise HTTPException(422, 'Укажите причину жалобы')
    rate_limit(db, 'product-report:' + buyer.id, 10, window=86400)
    db.add(ProductReport(id=secrets.token_hex(16),
        buyer_id=buyer.id, product_id=product_id, reason=body.reason.strip()))
    db.commit()
    return {'saved': True}


def take_down(db: Session, product_id: str, moderator_id: str, reason: str) -> None:
    product = db.get(Product, product_id)
    owner = db.get(MerchantProduct, product_id)
    if product is None or (owner is not None and owner.status == 'deleted'):
        raise HTTPException(404, 'Товар не найден')
    if is_held(db, product_id):
        raise HTTPException(409, 'Товар уже снят модератором')
    # Lock seller row in the same order as merchant operations; concurrent
    # publication and enforcement serialize on PostgreSQL.
    from .models import Seller
    if owner is not None:
        db.scalar(select(Seller).where(Seller.id == owner.seller_id).with_for_update(of=Seller))
        db.refresh(owner)
        if is_held(db, product_id):
            raise HTTPException(409, 'Товар уже снят модератором')
        from .merchant_operations import drop_offer
        for row in db.scalars(select(MerchantListing).where(
            MerchantListing.product_id == product_id)).all():
            if row.offer_id:
                drop_offer(db, row)
            if row.status == 'approved':
                row.status = 'paused'
    # Legacy/demo catalog entries have no MerchantProduct row. Keep their old
    # offers intact for history; the visibility flag hides them from all buyers.
    if product.details is None:
        product.details = ProductDetails(active=False, sizes=[])
    product.details.active = False
    now = time.time()
    hold = db.get(ProductSafetyHold, product_id)
    if hold is None:
        db.add(ProductSafetyHold(product_id=product_id, active=True,
            reason=reason, moderator_id=moderator_id, updated_at=now))
    else:
        hold.active = True
        hold.reason = reason
        hold.moderator_id = moderator_id
        hold.updated_at = now
    if owner is not None:
        owner.note = reason
    buyer_id = db.scalar(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == owner.seller_id,
        ShopMembership.role == 'owner')) if owner is not None else None
    if buyer_id:
        db.add(SellerNotification(
            id=secrets.token_hex(16), buyer_id=buyer_id,
            event_type='product_safety', status='removed',
            target_id=product_id, title='Товар снят с публикации',
            message=f'Товар «{product.title}» снят с публикации модератором.',
            note=reason, created_at=now))
