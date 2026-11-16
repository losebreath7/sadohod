"""Additive buyer features for v0.8.1.

All new tables are created separately from v0.8 tables; no destructive
migration, no changes to seller/admin data, sessions or Docker volumes.
"""
import base64
import binascii
import io
import hmac
import secrets
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import Float, ForeignKey, Integer, String, Text, LargeBinary, delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column
from PIL import Image, ImageOps, UnidentifiedImageError

from .account import Buyer, current_buyer, digest, hash_code, rate_limit, send_code, smtp_config, EmailInput
from .database import Base, get_db

router = APIRouter(prefix='/api/v1')


class BuyerMedia(Base):
    __tablename__ = 'buyer_profile_media'
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), primary_key=True)
    avatar: Mapped[str] = mapped_column(Text, default='', nullable=False)
    cover: Mapped[str] = mapped_column(Text, default='', nullable=False)


class BuyerEmailChange(Base):
    __tablename__ = 'buyer_email_change_codes'
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), nullable=False)
    digest: Mapped[str] = mapped_column(String(128), nullable=False)
    expires: Mapped[float] = mapped_column(Float, nullable=False)
    sent: Mapped[float] = mapped_column(Float, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class BuyerMessage(Base):
    __tablename__ = 'buyer_messages'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    sent: Mapped[float] = mapped_column(Float, nullable=False)
    staff: Mapped[bool] = mapped_column(default=False)


class BuyerChatAttachment(Base):
    __tablename__ = 'buyer_chat_attachments_v083'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id'), index=True)
    message_id: Mapped[str] = mapped_column(String(32), index=True)
    filename: Mapped[str] = mapped_column(String(128), nullable=False)
    mime: Mapped[str] = mapped_column(String(48), nullable=False)
    raw: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    preview: Mapped[str] = mapped_column(Text, default='', nullable=False)


class ChatAutoReply(Base):
    __tablename__ = 'chat_auto_replies'
    buyer: Mapped[str] = mapped_column(String(32), ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), primary_key=True)
    event: Mapped[str] = mapped_column(String(24), primary_key=True)
    message_id: Mapped[str] = mapped_column(String(32), nullable=False)


AUTO_REPLY_TEXT = {
    'greeting': 'привет, что тебя беспокоит?',
    'first_ack': 'запрос передан менеджеру, ожидаем ответа, помним о бренности бытия',
}


def create_auto_reply(db: Session, buyer_id: str, kind: str, event: str) -> bool:
    """Claim a message type atomically; marker and message share one transaction."""
    content = AUTO_REPLY_TEXT[event]
    if kind not in {'support', 'cooperation', 'm_support', 'm_cooperation'}:
        raise ValueError('Invalid chat kind')
    if db.get_bind().dialect.name == 'postgresql':
        from sqlalchemy.dialects.postgresql import insert
    elif db.get_bind().dialect.name == 'sqlite':
        from sqlalchemy.dialects.sqlite import insert
    else:
        raise RuntimeError('Unsupported chat database')
    db.flush()  # Keep the acknowledgement after the pending user message.
    message_id = secrets.token_hex(16)
    claimed = db.scalar(insert(ChatAutoReply).values(
        buyer=buyer_id, kind=kind, event=event, message_id=message_id,
    ).on_conflict_do_nothing(index_elements=['buyer', 'kind', 'event'])
      .returning(ChatAutoReply.message_id))
    if claimed is None:
        return False
    sent = time.time() + 0.0001
    if event == 'greeting':
        earliest = db.scalar(select(BuyerMessage.sent).where(
            BuyerMessage.buyer == buyer_id, BuyerMessage.kind == kind,
        ).order_by(BuyerMessage.sent.asc()).limit(1))
        sent = earliest - 0.001 if earliest is not None else time.time()
    db.add(BuyerMessage(id=message_id, buyer=buyer_id, kind=kind,
                       text=content, staff=True, sent=sent))
    return True


class MediaInput(BaseModel):
    kind: Literal['avatar', 'cover']
    data: str = Field(min_length=10, max_length=2_000_000)


@router.get('/account/media')
def get_media(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = db.get(BuyerMedia, buyer.id)
    return {'avatar': row.avatar if row else '', 'cover': row.cover if row else ''}


@router.post('/account/media')
def change_media(body: MediaInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    try:
        data = base64.b64decode(body.data, validate=True)
    except (ValueError, binascii.Error):
        raise HTTPException(422, 'Некорректное изображение') from None
    if len(data) > 1_500_000:
        raise HTTPException(413, 'Изображение должно быть меньше 1,5 МБ')
    try:
        with Image.open(io.BytesIO(data)) as im:
            if im.format not in {'JPEG', 'PNG', 'WEBP'}:
                raise HTTPException(422, 'Поддерживаются JPG, PNG и WebP')
            # Reencode to avoid storing user-supplied metadata and reduce size.
            im = ImageOps.exif_transpose(im)
            im.thumbnail((1600, 900) if body.kind == 'cover' else (600, 600))
            rgb = im.convert('RGB')
            buf = io.BytesIO()
            rgb.save(buf, format='JPEG', quality=78, optimize=True)
        encoded = base64.b64encode(buf.getvalue()).decode('ascii')
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(422, 'Не удалось прочитать изображение') from None
    if len(encoded) > 1_500_000:
        raise HTTPException(413, 'Слишком большое изображение')
    row = db.get(BuyerMedia, buyer.id)
    if row is None:
        row = BuyerMedia(buyer=buyer.id, avatar='', cover='')
        db.add(row)
    setattr(row, body.kind, encoded)
    db.commit()
    return {'saved': True}


class EmailChangeVerify(EmailInput):
    code: str = Field(pattern=r'^\d{6}$')


@router.post('/account/email/request')
def request_change(body: EmailInput, request: Request,
                   buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    smtp_config()
    if buyer.email == body.email:
        raise HTTPException(400, 'Это ваша текущая почта')
    ip = request.client.host if request.client else 'unknown'
    rate_limit(db, 'email-change-ip:' + digest(ip), 12)
    rate_limit(db, 'email-change-account:' + buyer.id, 5)
    rate_limit(db, 'email-change-to:' + digest(body.email), 5)
    now = time.time()
    code = f'{secrets.randbelow(1_000_000):06d}'
    hashed = hash_code(code)
    values = dict(email=body.email, digest=hashed, expires=now + 600, sent=now, attempts=0)
    changed = db.execute(update(BuyerEmailChange).where(
        BuyerEmailChange.buyer == buyer.id, BuyerEmailChange.sent <= now - 60
    ).values(**values))
    if not changed.rowcount:
        db.add(BuyerEmailChange(buyer=buyer.id, **values))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(429, 'Повторный код можно запросить через минуту.') from None
    try:
        send_code(body.email, code)
    except Exception:
        db.execute(delete(BuyerEmailChange).where(
            BuyerEmailChange.buyer == buyer.id, BuyerEmailChange.digest == hashed))
        db.commit()
        raise HTTPException(503, 'Не удалось отправить письмо. Попробуйте позже.') from None
    return {'sent': True, 'expires_in': 600}


@router.post('/account/email/confirm')
def confirm_change(body: EmailChangeVerify, request: Request,
                   buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    ip = request.client.host if request.client else 'unknown'
    rate_limit(db, 'change-verify-ip:' + digest(ip), 60)
    invalid = 'Код неверный или истёк'
    reserved = db.execute(update(BuyerEmailChange).where(
        BuyerEmailChange.buyer == buyer.id,
        BuyerEmailChange.email == body.email,
        BuyerEmailChange.expires > time.time(),
        BuyerEmailChange.attempts < 5,
    ).values(attempts=BuyerEmailChange.attempts + 1).returning(BuyerEmailChange.digest)).scalar_one_or_none()
    if reserved is None:
        db.rollback()
        raise HTTPException(400, invalid)
    if not hmac.compare_digest(reserved, hash_code(body.code, reserved.split(':')[0])):
        db.commit()
        raise HTTPException(400, invalid)
    db.execute(delete(BuyerEmailChange).where(BuyerEmailChange.buyer == buyer.id))
    try:
        with db.begin_nested():
            buyer.email = body.email
            db.flush()
    except IntegrityError:
        # Consume the confirmed challenge even when the address is already taken.
        db.commit()
        raise HTTPException(400, 'Не удалось изменить почту. Выберите другой адрес.') from None
    db.commit()
    return {'saved': True, 'email': buyer.email}



def attachment_infos(db: Session, buyer_id: str, message_ids: list[str]) -> dict:
    """Load metadata and thumbnails for the visible page, never file bodies."""
    if not message_ids:
        return {}
    rows = db.execute(select(
        BuyerChatAttachment.message_id, BuyerChatAttachment.id,
        BuyerChatAttachment.filename, BuyerChatAttachment.mime,
        BuyerChatAttachment.preview,
    ).where(
        BuyerChatAttachment.buyer == buyer_id,
        BuyerChatAttachment.message_id.in_(message_ids),
    )).all()
    result = {}
    for row in rows:
        result.setdefault(row.message_id, {
            'id': row.id, 'filename': row.filename,
            'mime': row.mime, 'preview': row.preview,
        })
    return result


class ChatAttachmentInput(BaseModel):
    kind: Literal['support', 'cooperation']
    filename: str = Field(min_length=1, max_length=128)
    data: str = Field(min_length=4, max_length=4_300_000)
    text: str = Field(default='', max_length=1000)
    auto_ack: bool = False


def attachment_bytes(filename: str, encoded: str) -> tuple[bytes, str, str, str]:
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise HTTPException(422, 'Некорректное вложение') from None
    if not (1 <= len(raw) <= 3_000_000):
        raise HTTPException(413, 'Максимальный размер файла — 3 МБ')
    safe = ''.join(c for c in filename if c.isalnum() or c in '._- ')[:96].strip('. ')
    safe = safe or 'file'
    lower = safe.lower()
    if lower.endswith(('.jpg', '.jpeg', '.png', '.webp')):
        try:
            with Image.open(io.BytesIO(raw)) as im:
                if im.format not in ('JPEG','PNG','WEBP'):
                    raise ValueError('wrong image')
                im = ImageOps.exif_transpose(im)
                im.thumbnail((1400, 1400))
                b = io.BytesIO()
                im.convert('RGB').save(b, format='JPEG', quality=75, optimize=True)
                raw = b.getvalue()
                im.thumbnail((360, 360))
                thumb = io.BytesIO()
                im.convert('RGB').save(thumb, format='JPEG', quality=55)
                preview = base64.b64encode(thumb.getvalue()).decode('ascii')
            return raw, 'image/jpeg', safe.rsplit('.',1)[0]+'.jpg', preview
        except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError):
            raise HTTPException(422, 'Некорректная фотография') from None
    if lower.endswith('.pdf') and raw.startswith(b'%PDF-'):
        return raw, 'application/pdf', safe, ''
    if lower.endswith('.txt'):
        try:
            raw.decode('utf-8')
        except UnicodeDecodeError:
            raise HTTPException(422, 'Текстовый файл должен быть в UTF-8') from None
        return raw, 'text/plain', safe, ''
    raise HTTPException(422, 'Поддерживаются JPG, PNG, WebP, PDF и TXT')


@router.post('/account/messages/attachment')
def send_attachment(body: ChatAttachmentInput, buyer: Buyer = Depends(current_buyer),
                    db: Session = Depends(get_db)):
    rate_limit(db, 'attachment:'+buyer.id, 15, window=3600)
    raw, mime, filename, preview = attachment_bytes(body.filename, body.data)
    label = body.text.strip() or ('Фото' if mime.startswith('image/') else 'Файл: '+filename)
    item = BuyerMessage(id=secrets.token_hex(16), buyer=buyer.id, kind=body.kind,
                        text=label, sent=time.time(), staff=False)
    db.add(item)
    attachment = BuyerChatAttachment(id=secrets.token_hex(16), buyer=buyer.id,
        message_id=item.id, filename=filename, mime=mime, raw=raw, preview=preview)
    db.add(attachment)
    from .telegram_bridge import make_outbox
    if body.auto_ack:
        create_first_auto_ack(db, buyer.id, body.kind)
    make_outbox(db, item)
    db.commit()
    return {'stored': True, 'id': item.id}


@router.get('/account/messages/attachment/{attachment_id}')
def get_attachment(attachment_id: str, buyer: Buyer = Depends(current_buyer),
                   db: Session = Depends(get_db)):
    item = db.get(BuyerChatAttachment, attachment_id)
    if item is None or item.buyer != buyer.id:
        raise HTTPException(404, 'Файл не найден')
    from urllib.parse import quote
    return Response(content=item.raw, media_type='application/octet-stream', headers={
        'X-Content-Type-Options': 'nosniff',
        'Content-Disposition': "attachment; filename*=UTF-8''"+quote(item.filename),
        'Cache-Control': 'no-store',
    })


def create_first_auto_ack(db: Session, buyer_id: str, kind: str) -> None:
    create_auto_reply(db, buyer_id, kind, 'first_ack')


class BuyerMessageInput(BaseModel):
    kind: Literal['support', 'cooperation']
    text: str = Field(min_length=1, max_length=2000)
    auto_ack: bool = False  # opt-in for the updated buyer chat; legacy clients stay compatible


@router.get('/account/messages')
def messages(kind: Literal['support', 'cooperation'], with_greeting: bool = False,
             buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    if with_greeting:
        create_auto_reply(db, buyer.id, kind, 'greeting')
        db.commit()
    # Newest 100 in chronological order. Older SQL used ASC LIMIT 100, which
    # permanently hid new manager replies in long-running conversations.
    rows = db.scalars(select(BuyerMessage).where(BuyerMessage.buyer == buyer.id,
            BuyerMessage.kind == kind).order_by(BuyerMessage.sent.desc()).limit(100)).all()
    rows.reverse()
    attachments = attachment_infos(db, buyer.id, [r.id for r in rows])
    items = []
    for r in rows:
        attachment = attachments.get(r.id)
        msg = {'id':r.id, 'text':r.text, 'sent':r.sent, 'staff':r.staff}
        if attachment:
            msg['attachment'] = attachment
        items.append(msg)
    return {'items': items}


@router.post('/account/messages')
def send_message(body: BuyerMessageInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    rate_limit(db, 'message:' + buyer.id, 30, window=3600)
    text = body.text.strip()
    if not text:
        raise HTTPException(422, 'Сообщение пустое')
    item = BuyerMessage(id=secrets.token_hex(16), buyer=buyer.id, kind=body.kind,
                        text=text, sent=time.time(), staff=False)
    db.add(item)
    # Backend acknowledgement only for the new chat UI, after the first
    # successful user message; never send this acknowledgement to Telegram.
    if body.auto_ack:
        create_first_auto_ack(db, buyer.id, body.kind)
    from .telegram_bridge import make_outbox
    make_outbox(db, item)
    db.commit()
    return {'stored': True, 'id': item.id}
