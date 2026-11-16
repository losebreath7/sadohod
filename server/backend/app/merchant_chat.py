"""Seller-only support and cooperation conversations, using the existing Telegram bridge.

Seller chat kinds are distinct from buyer chat kinds, but use the same durable
outbox, inbound deduplication and per-user authentication. No new tables.
"""
import secrets
import time
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session
from .account import Buyer, current_buyer
from .database import get_db
from .merchant_models import ShopApplication, ShopMembership
from .buyer_extras import (
    BuyerMessage, BuyerChatAttachment, attachment_bytes, attachment_infos,
    create_auto_reply, create_first_auto_ack, rate_limit,
)
from .telegram_bridge import make_outbox

router = APIRouter(prefix='/api/v1/merchant/chat', tags=['Merchant chat'])
KINDS = {'support': 'm_support', 'cooperation': 'm_cooperation'}


def seller_guard(buyer: Buyer, db: Session):
    membership = db.scalar(select(ShopMembership.buyer_id).where(ShopMembership.buyer_id == buyer.id).limit(1))
    application = db.scalar(select(ShopApplication.id).where(ShopApplication.buyer_id == buyer.id).limit(1))
    if not membership and not application:
        raise HTTPException(403, 'Доступно только зарегистрированным продавцам')


class MessageInput(BaseModel):
    kind: Literal['support', 'cooperation']
    text: str = Field(min_length=1, max_length=2000)


@router.get('/messages')
def messages(kind: Literal['support', 'cooperation'], buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller_guard(buyer, db)
    namespace = KINDS[kind]
    create_auto_reply(db, buyer.id, namespace, 'greeting')
    db.commit()
    records = db.scalars(select(BuyerMessage).where(BuyerMessage.buyer == buyer.id,
        BuyerMessage.kind == namespace).order_by(BuyerMessage.sent.desc()).limit(100)).all()
    attachments = attachment_infos(db, buyer.id, [m.id for m in records])
    return {'items': [{'id': m.id, 'text': m.text, 'sent': m.sent, 'staff': m.staff,
        **({'attachment': attachments[m.id]} if m.id in attachments else {})}
        for m in reversed(records)]}


@router.post('/messages', status_code=201)
def send(body: MessageInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller_guard(buyer, db)
    rate_limit(db, 'merchant_message:' + buyer.id, 30, window=3600)
    content = body.text.strip()
    if not content:
        raise HTTPException(422, 'Сообщение пустое')
    kind = KINDS[body.kind]
    message = BuyerMessage(id=secrets.token_hex(16), buyer=buyer.id, kind=kind,
        text=content, sent=time.time(), staff=False)
    db.add(message)
    create_first_auto_ack(db, buyer.id, kind)
    make_outbox(db, message)
    db.commit()
    return {'stored': True, 'id': message.id}


class SellerAttachmentInput(BaseModel):
    kind: Literal['support', 'cooperation']
    filename: str = Field(min_length=1, max_length=128)
    data: str = Field(min_length=4, max_length=4_300_000)
    text: str = Field(default='', max_length=1000)


@router.post('/messages/attachment', status_code=201)
def send_attachment(body: SellerAttachmentInput, buyer: Buyer = Depends(current_buyer),
                    db: Session = Depends(get_db)):
    """Same guarded attachment flow as buyer chat, with distinct seller kinds."""
    seller_guard(buyer, db)
    rate_limit(db, 'merchant_attachment:' + buyer.id, 15, window=3600)
    raw, mime, filename, preview = attachment_bytes(body.filename, body.data)
    kind = KINDS[body.kind]
    label = body.text.strip() or ('Фото' if mime.startswith('image/') else 'Файл: ' + filename)
    item = BuyerMessage(id=secrets.token_hex(16), buyer=buyer.id, kind=kind,
                        text=label, sent=time.time(), staff=False)
    db.add(item)
    db.add(BuyerChatAttachment(id=secrets.token_hex(16), buyer=buyer.id,
        message_id=item.id, filename=filename, mime=mime, raw=raw, preview=preview))
    create_first_auto_ack(db, buyer.id, kind)
    make_outbox(db, item)
    db.commit()
    return {'stored': True, 'id': item.id}
