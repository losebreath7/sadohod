"""Seller notification inbox.

Notifications are recorded in the same SQLAlchemy transaction that changes a
moderated entity. No Telegram job, mutable global state, or client-side
fabrication of moderation statuses is involved.
"""
import time
import uuid
from typing import Optional, Literal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import Float, ForeignKey, String, Text, select, event, inspect, func
from sqlalchemy.orm import Mapped, mapped_column, Session

from .account import Buyer, current_buyer
from .database import Base, get_db
from .merchant_models import (ShopApplication, PavilionRequest, MerchantProduct,
                              MerchantListing, ShopMembership)
from .models import Product, Pavilion

router = APIRouter(prefix='/api/v1/merchant/notifications',
                   tags=['Seller notifications'])


class SellerNotification(Base):
    __tablename__ = 'merchant_notifications'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer_id: Mapped[str] = mapped_column(
        ForeignKey('buyers.id', ondelete='CASCADE'), index=True, nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    target_id: Mapped[str] = mapped_column(String(32), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    note: Mapped[str] = mapped_column(Text, default='', nullable=False)
    created_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
    read_at: Mapped[Optional[float]] = mapped_column(Float, nullable=True)


def _status_transition(db: Session, row, status: str):
    state = inspect(row)
    history = state.attrs.status.history
    if state.pending:
        # SQLAlchemy column defaults are applied at INSERT, not beforehand.
        return status in (None, 'pending')
    return bool(history.has_changes() and status != (history.deleted[0]
        if history.deleted else None))


def _recipient(db: Session, seller_id: str) -> str | None:
    return db.scalar(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == seller_id, ShopMembership.role == 'owner'))


def _record(db: Session, buyer_id: str | None, kind: str, target: str,
            status: str, subject: str, note: str = '', previous_status: str | None = None):
    if buyer_id is None or status not in ('pending', 'approved', 'rejected'):
        return
    # Publishing a normal draft immediately is NOT a moderator decision.
    # Emit a positive product/listing notice only after a real pending review.
    # Pending and rejected transitions are always meaningful to the seller.
    if kind in ('product', 'listing') and status == 'approved' and previous_status != 'pending':
        return
    subject = (subject or 'Без названия').strip()
    titles = {
        'application': {
            'pending': 'Заявка на магазин отправлена',
            'approved': 'Магазин подтверждён',
            'rejected': 'Заявка на магазин отклонена',
        },
        'pavilion': {
            'pending': 'Павильон на проверке',
            'approved': 'Павильон подтверждён',
            'rejected': 'Павильон отклонён',
        },
        'product': {
            'pending': 'Товар на проверке',
            'approved': 'Товар опубликован',
            'rejected': 'Товар не прошёл модерацию',
        },
        'listing': {
            'pending': 'Размещение на проверке',
            'approved': 'Размещение одобрено',
            'rejected': 'Размещение отклонено',
        },
    }
    subject_label = {
        'application': 'Магазин',
        'pavilion': 'Павильон',
        'product': 'Товар',
        'listing': 'Размещение товара',
    }[kind]
    messages = {
        'pending': f'{subject_label} «{subject}» отправлен на проверку.',
        'approved': f'{subject_label} «{subject}» прошёл проверку.',
        'rejected': f'{subject_label} «{subject}» отклонён.',
    }
    if kind == 'listing':
        messages = {
            'pending': f'Размещение «{subject}» отправлено на проверку.',
            'approved': f'Размещение «{subject}» одобрено.',
            'rejected': f'Размещение «{subject}» отклонено.',
        }
    title = titles[kind][status]
    db.add(SellerNotification(
        id=uuid.uuid4().hex, buyer_id=buyer_id, event_type=kind,
        status=status, target_id=target, title=title,
        message=messages[status],
        note=note if status == 'rejected' else '', created_at=time.time()))


@event.listens_for(Session, 'before_flush')
def _capture_merchant_decisions(db, flush_context, instances):
    # Attribute-history inspection catches only real transitions; updating
    # unrelated columns, polling and restarting the API cannot duplicate them.
    # The newly inserted notification shares the original transaction, so a
    # failed moderation decision cannot leave a false notification behind.
    # Approving/rejecting a product may update all its placements in one
    # transaction. Record the product decision once; standalone placement
    # decisions remain independent notifications.
    changed_products = {
        obj.product_id for obj in list(db.new) + list(db.dirty)
        if isinstance(obj, MerchantProduct)
        and _status_transition(db, obj, obj.status)
        and obj.status in ('pending', 'approved', 'rejected')
    }
    # publish_listing() may flush more than once inside the same product
    # decision. Suppress its placement notices for the *whole transaction*,
    # not just a single before_flush pass.
    covered_products = db.info.setdefault('_seller_notified_product_ids', set())
    covered_products.update(changed_products)
    for obj in list(db.new) + list(db.dirty):
        if isinstance(obj, MerchantListing) and obj.product_id in covered_products:
            continue
        if not isinstance(obj, (ShopApplication, PavilionRequest,
                                MerchantProduct, MerchantListing)):
            continue
        status = obj.status
        if not _status_transition(db, obj, status):
            continue
        if status is None:
            status = 'pending'
        history = inspect(obj).attrs.status.history
        previous_status = history.deleted[0] if history.deleted else None
        if isinstance(obj, ShopApplication):
            _record(db, obj.buyer_id, 'application', obj.id, status,
                    f'{obj.zone}-{obj.code}', obj.note)
        elif isinstance(obj, PavilionRequest):
            _record(db, _recipient(db, obj.seller_id), 'pavilion',
                    obj.id, status, f'{obj.zone}-{obj.code}', obj.note)
        elif isinstance(obj, MerchantProduct):
            p = db.get(Product, obj.product_id)
            _record(db, _recipient(db, obj.seller_id), 'product',
                    obj.product_id, status, p.title if p else 'Товар', obj.note,
                    previous_status=previous_status)
        elif isinstance(obj, MerchantListing):
            product = db.get(Product, obj.product_id)
            pavilion = db.get(Pavilion, obj.pavilion_id)
            subject = product.title if product else 'Товар'
            if pavilion:
                subject += f' · {pavilion.zone}-{pavilion.code}'
            _record(db, _recipient(db, obj.seller_id), 'listing',
                    obj.id, status, subject, obj.note,
                    previous_status=previous_status)


@event.listens_for(Session, 'after_commit')
@event.listens_for(Session, 'after_rollback')
def _clear_notification_decisions(db):
    # Session can be reused; decisions from a prior transaction cannot hide
    # future independent listing updates.
    db.info.pop('_seller_notified_product_ids', None)


def _owned(notification_id: str, buyer: Buyer, db: Session) -> SellerNotification:
    item = db.get(SellerNotification, notification_id)
    if item is None or item.buyer_id != buyer.id:
        raise HTTPException(404, 'Уведомление не найдено')
    return item


def _dto(row: SellerNotification):
    return {
        'id': row.id, 'event_type': row.event_type,
        'status': row.status, 'target_id': row.target_id, 'title': row.title,
        'message': row.message, 'note': row.note,
        'created_at': row.created_at, 'read': row.read_at is not None,
    }


@router.get('')
def notifications(scope: Literal['seller', 'courier'] = 'seller',
                  buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    role_filter = (SellerNotification.event_type == 'courier_review'
                   if scope == 'courier' else SellerNotification.event_type != 'courier_review')
    conditions = (SellerNotification.buyer_id == buyer.id, role_filter)
    rows = db.scalars(select(SellerNotification).where(*conditions)
        .order_by(SellerNotification.created_at.desc(), SellerNotification.id.desc())
        .limit(150)).all()
    unread = db.scalar(select(func.count()).select_from(SellerNotification).where(
        *conditions, SellerNotification.read_at.is_(None))) or 0
    return {'items': [_dto(row) for row in rows], 'unread': unread}


@router.put('/{notification_id}/read')
def mark_read(notification_id: str, buyer: Buyer = Depends(current_buyer),
              db: Session = Depends(get_db)):
    row = _owned(notification_id, buyer, db)
    if row.read_at is None:
        row.read_at = time.time()
        db.commit()
    return {'id': row.id, 'read': True}
