"""Seller notification inbox.

Notifications are recorded in the same SQLAlchemy transaction that changes a
moderated entity. No Telegram job, mutable global state, or client-side
fabrication of moderation statuses is involved.
"""
import time
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import Float, ForeignKey, String, Text, select, event, inspect
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
            status: str, subject: str, note: str = ''):
    if buyer_id is None or status not in ('pending', 'approved', 'rejected'):
        return
    subject = (subject or 'Без названия').strip()
    label = {
        'application': 'Магазин',
        'pavilion': 'Павильон',
        'product': 'Товар',
        'listing': 'Размещение товара',
    }[kind]
    action = {
        'pending': 'отправлен на проверку' if kind != 'application' else 'отправлена на проверку',
        'approved': 'прошёл модерацию' if kind != 'application' else 'подтверждён',
        'rejected': 'не прошёл модерацию' if kind != 'application' else 'отклонён',
    }[status]
    title = {
        'pending': 'На проверке',
        'approved': 'Проверка пройдена',
        'rejected': 'Не прошло модерацию',
    }[status]
    db.add(SellerNotification(
        id=uuid.uuid4().hex, buyer_id=buyer_id, event_type=kind,
        target_id=target, title=title,
        message=f'{label} «{subject}» {action}.',
        note=note if status == 'rejected' else '', created_at=time.time()))


@event.listens_for(Session, 'before_flush')
def _capture_merchant_decisions(db, flush_context, instances):
    # Attribute-history inspection catches only real transitions; updating
    # unrelated columns, polling and restarting the API cannot duplicate them.
    # The newly inserted notification shares the original transaction, so a
    # failed moderation decision cannot leave a false notification behind.
    for obj in list(db.new) + list(db.dirty):
        if not isinstance(obj, (ShopApplication, PavilionRequest,
                                MerchantProduct, MerchantListing)):
            continue
        status = obj.status
        if not _status_transition(db, obj, status):
            continue
        if status is None:
            status = 'pending'
        if isinstance(obj, ShopApplication):
            _record(db, obj.buyer_id, 'application', obj.id, status,
                    f'{obj.zone}-{obj.code}', obj.note)
        elif isinstance(obj, PavilionRequest):
            _record(db, _recipient(db, obj.seller_id), 'pavilion',
                    obj.id, status, f'{obj.zone}-{obj.code}', obj.note)
        elif isinstance(obj, MerchantProduct):
            p = db.get(Product, obj.product_id)
            _record(db, _recipient(db, obj.seller_id), 'product',
                    obj.product_id, status, p.title if p else 'Товар', obj.note)
        elif isinstance(obj, MerchantListing):
            product = db.get(Product, obj.product_id)
            pavilion = db.get(Pavilion, obj.pavilion_id)
            subject = product.title if product else 'Товар'
            if pavilion:
                subject += f' · {pavilion.zone}-{pavilion.code}'
            _record(db, _recipient(db, obj.seller_id), 'listing',
                    obj.id, status, subject, obj.note)


def _owned(notification_id: str, buyer: Buyer, db: Session) -> SellerNotification:
    item = db.get(SellerNotification, notification_id)
    if item is None or item.buyer_id != buyer.id:
        raise HTTPException(404, 'Уведомление не найдено')
    return item


def _dto(row: SellerNotification):
    return {
        'id': row.id, 'event_type': row.event_type,
        'target_id': row.target_id, 'title': row.title,
        'message': row.message, 'note': row.note,
        'created_at': row.created_at, 'read': row.read_at is not None,
    }


@router.get('')
def notifications(buyer: Buyer = Depends(current_buyer),
                  db: Session = Depends(get_db)):
    # Both first-time applicants and established sellers must see decisions.
    rows = db.scalars(select(SellerNotification).where(
        SellerNotification.buyer_id == buyer.id)
        .order_by(SellerNotification.created_at.desc(), SellerNotification.id.desc())
        .limit(150)).all()
    return {'items': [_dto(row) for row in rows],
            'unread': sum(row.read_at is None for row in rows)}


@router.put('/{notification_id}/read')
def mark_read(notification_id: str, buyer: Buyer = Depends(current_buyer),
              db: Session = Depends(get_db)):
    row = _owned(notification_id, buyer, db)
    if row.read_at is None:
        row.read_at = time.time()
        db.commit()
    return {'id': row.id, 'read': True}
