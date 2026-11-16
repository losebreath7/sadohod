"""Buyer email OTP, revocable sessions and account-scoped favourites.
SMTP must be configured explicitly; no development code is returned over HTTP.
"""
import hashlib
import hmac
import os
import re
import secrets
import smtplib
import ssl
import time
from email.message import EmailMessage
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import Float, Integer, String, UniqueConstraint, delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column
from .database import Base, get_db

router = APIRouter(prefix='/api/v1')

class Buyer(Base):
    __tablename__ = 'buyers'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    name: Mapped[str] = mapped_column(String(80), default='')

class LoginCode(Base):
    __tablename__ = 'buyer_login_codes'
    email: Mapped[str] = mapped_column(String(254), primary_key=True)
    digest: Mapped[str] = mapped_column(String(128))
    expires: Mapped[float] = mapped_column(Float)
    sent: Mapped[float] = mapped_column(Float)
    attempts: Mapped[int] = mapped_column(Integer, default=0)

class BuyerSession(Base):
    __tablename__ = 'buyer_sessions'
    digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    buyer: Mapped[str] = mapped_column(String(32), index=True)
    expires: Mapped[float] = mapped_column(Float)

class Favorite(Base):
    __tablename__ = 'buyer_favorites'
    buyer: Mapped[str] = mapped_column(String(32), primary_key=True)
    kind: Mapped[str] = mapped_column(String(8), primary_key=True)
    item: Mapped[str] = mapped_column(String(32), primary_key=True)

class RateBucket(Base):
    __tablename__ = 'buyer_rate_buckets'
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    count: Mapped[int] = mapped_column(Integer)
    expires: Mapped[float] = mapped_column(Float)

class EmailInput(BaseModel):
    email: str = Field(max_length=254)
    @field_validator('email')
    @classmethod
    def validate_email(cls, value):
        value = value.strip().lower()
        if not re.fullmatch(r'[^\s@\x00-\x1f]+@[^\s@\x00-\x1f]+\.[^\s@\x00-\x1f]+', value):
            raise ValueError('Некорректная почта')
        return value

class VerifyInput(EmailInput):
    code: str = Field(pattern=r'^\d{6}$')

class FavoriteInput(BaseModel):
    kind: Literal['product', 'seller']
    id: str = Field(min_length=1, max_length=32)
    saved: bool

class MergeInput(BaseModel):
    products: list[str] = Field(default_factory=list, max_length=500)
    sellers: list[str] = Field(default_factory=list, max_length=500)
    @field_validator('products', 'sellers')
    @classmethod
    def ids(cls, values):
        if any(not v or len(v) > 32 for v in values):
            raise ValueError('Некорректный ID')
        return list(dict.fromkeys(values))

class ProfileInput(BaseModel):
    name: str = Field(max_length=80)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def hash_code(code, salt=None):
    salt = salt or secrets.token_hex(16)
    # Slow salted KDF limits offline guessing if only the database is leaked.
    value = hashlib.pbkdf2_hmac('sha256', code.encode(), bytes.fromhex(salt), 200_000).hex()
    return salt + ':' + value


def smtp_config():
    host, sender = os.getenv('SMTP_HOST', ''), os.getenv('SMTP_FROM', '')
    if not host or not sender:
        raise HTTPException(503, 'Отправка писем ещё не подключена. Избранное доступно без входа.')
    return host, sender


def send_code(email, code):
    host, sender = smtp_config()
    msg = EmailMessage()
    msg['From'], msg['To'], msg['Subject'] = sender, email, 'Код входа в Садоход'
    msg.set_content(f'Ваш код: {code}\nДействует 10 минут. Никому не сообщайте код.\nЕсли вы не запрашивали вход, проигнорируйте письмо.')
    port = int(os.getenv('SMTP_PORT', '465'))
    context = ssl.create_default_context()
    if port == 465:
        client = smtplib.SMTP_SSL(host, port, timeout=15, context=context)
    else:
        client = smtplib.SMTP(host, port, timeout=15)
    with client:
        if port != 465:
            client.starttls(context=context)
        if os.getenv('SMTP_USER'):
            client.login(os.environ['SMTP_USER'], os.environ.get('SMTP_PASSWORD', ''))
        client.send_message(msg)


def rate_limit(db, key, maximum, window=3600):
    now = time.time()
    bucket = f'{key}:{int(now // window)}'
    # Savepoint handles a simultaneous first insert without discarding the request transaction.
    if db.get(RateBucket, bucket) is None:
        try:
            with db.begin_nested():
                db.add(RateBucket(key=bucket, count=0, expires=now+window))
                db.flush()
        except IntegrityError:
            pass
    result = db.execute(update(RateBucket).where(RateBucket.key == bucket, RateBucket.count < maximum).values(count=RateBucket.count + 1))
    db.commit()
    if not result.rowcount:
        # Include a safe retry duration; never disclose the bucket identity.
        remaining = max(1, int((int(now // window) + 1) * window - now) + 1)
        minutes = max(1, (remaining + 59) // 60)
        raise HTTPException(
            429,
            f'Слишком много попыток. Повторите через {minutes} мин.',
            headers={'Retry-After': str(remaining)},
        )


@router.post('/auth/code')
def request_code(body: EmailInput, request: Request, db: Session = Depends(get_db)):
    smtp_config()
    ip = request.client.host if request.client else 'unknown'
    rate_limit(db, 'mail-ip:' + digest(ip), 20)
    rate_limit(db, 'mail:' + digest(body.email), 5)
    now, code = time.time(), f'{secrets.randbelow(1_000_000):06d}'
    db.execute(delete(RateBucket).where(RateBucket.expires < now-3600))
    db.execute(delete(BuyerSession).where(BuyerSession.expires < now))
    hashed = hash_code(code)
    old = db.get(LoginCode, body.email)
    if old:
        result = db.execute(update(LoginCode).where(LoginCode.email == body.email, LoginCode.sent <= now-60).values(digest=hashed, sent=now, expires=now+600, attempts=0))
        if not result.rowcount:
            db.rollback()
            raise HTTPException(429, 'Повторный код можно запросить через минуту.')
    else:
        db.add(LoginCode(email=body.email, digest=hashed, sent=now, expires=now+600, attempts=0))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(429, 'Код уже запрошен. Подождите минуту.')
    try:
        send_code(body.email, code)
    except Exception:
        db.execute(delete(LoginCode).where(LoginCode.email == body.email, LoginCode.digest == hashed))
        db.commit()
        raise HTTPException(503, 'Не удалось отправить письмо. Попробуйте позже.') from None
    return {'sent': True, 'retry_after': 60, 'expires_in': 600}


@router.post('/auth/verify')
def verify(body: VerifyInput, request: Request, db: Session = Depends(get_db)):
    rate_limit(db, 'verify-ip:' + digest(request.client.host if request.client else 'unknown'), 60)
    now = time.time()
    # Atomic increment prevents concurrent guesses from bypassing the attempt limit.
    updated = db.execute(update(LoginCode).where(LoginCode.email == body.email, LoginCode.expires > now, LoginCode.attempts < 5).values(attempts=LoginCode.attempts+1))
    if not updated.rowcount:
        db.rollback()
        raise HTTPException(400, 'Код неверный или истёк. Запросите новый.')
    row = db.get(LoginCode, body.email)
    salt = row.digest.split(':')[0]
    correct = hmac.compare_digest(row.digest, hash_code(body.code, salt))
    if not correct:
        db.commit()
        raise HTTPException(400, 'Код неверный или истёк. Запросите новый.')
    db.delete(row)  # Consumed once in the same transaction as session creation.
    buyer = db.scalar(select(Buyer).where(Buyer.email == body.email))
    if buyer is None:
        buyer = Buyer(id=secrets.token_hex(16), email=body.email, name='')
        db.add(buyer)
    token = secrets.token_urlsafe(32)
    db.add(BuyerSession(digest=digest(token), buyer=buyer.id, expires=now+30*86400))
    db.commit()
    return {'token': token, 'expires_in': 30*86400}


def current_buyer(authorization: str = Header(default=''), db: Session = Depends(get_db)):
    raw = authorization.removeprefix('Bearer ') if authorization.startswith('Bearer ') else ''
    session = db.get(BuyerSession, digest(raw)) if raw else None
    buyer = db.get(Buyer, session.buyer) if session and session.expires > time.time() else None
    if buyer is None:
        raise HTTPException(401, 'Войдите в аккаунт заново.')
    return buyer


@router.get('/account')
def account(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    rows = db.scalars(select(Favorite).where(Favorite.buyer == buyer.id)).all()
    return {'email': buyer.email, 'name': buyer.name,
            'products': [f.item for f in rows if f.kind == 'product'],
            'sellers': [f.item for f in rows if f.kind == 'seller']}


def add_favorite(db, buyer, kind, item):
    if db.get(Favorite, (buyer, kind, item)) is None:
        try:
            with db.begin_nested():
                db.add(Favorite(buyer=buyer, kind=kind, item=item))
                db.flush()
        except IntegrityError:
            pass


@router.post('/account/favorite')
def favorite(body: FavoriteInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    if body.saved:
        add_favorite(db, buyer.id, body.kind, body.id)
    else:
        db.execute(delete(Favorite).where(Favorite.buyer == buyer.id, Favorite.kind == body.kind, Favorite.item == body.id))
    db.commit()
    return {'saved': body.saved}


@router.post('/account/merge')
def merge(body: MergeInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    for kind, values in [('product', body.products), ('seller', body.sellers)]:
        for item in values:
            add_favorite(db, buyer.id, kind, item)
    db.commit()
    return {'ok': True}


@router.post('/account/profile')
def profile(body: ProfileInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    buyer.name = body.name.strip()
    db.commit()
    return {'ok': True}


@router.post('/auth/logout')
def logout(authorization: str = Header(default=''), buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.execute(delete(BuyerSession).where(BuyerSession.digest == digest(authorization.removeprefix('Bearer '))))
    db.commit()
    return {'ok': True}


@router.delete('/account')
def remove_account(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.execute(delete(Favorite).where(Favorite.buyer == buyer.id))
    db.execute(delete(BuyerSession).where(BuyerSession.buyer == buyer.id))
    db.execute(delete(LoginCode).where(LoginCode.email == buyer.email))
    from .buyer_extras import BuyerMedia, BuyerEmailChange, BuyerMessage, BuyerChatAttachment, ChatAutoReply
    from .telegram_bridge import TelegramTopic, TelegramOutbox
    # Stop forwarding any queued messages for a deleted account.
    db.execute(delete(TelegramOutbox).where(TelegramOutbox.buyer == buyer.id))
    db.execute(delete(TelegramTopic).where(TelegramTopic.buyer == buyer.id))
    db.execute(delete(BuyerMedia).where(BuyerMedia.buyer == buyer.id))
    db.execute(delete(BuyerEmailChange).where(BuyerEmailChange.buyer == buyer.id))
    db.execute(delete(BuyerChatAttachment).where(BuyerChatAttachment.buyer == buyer.id))
    db.execute(delete(ChatAutoReply).where(ChatAutoReply.buyer == buyer.id))
    db.execute(delete(BuyerMessage).where(BuyerMessage.buyer == buyer.id))
    from .buyer_reviews_v082 import BuyerSellerNote, SellerReview, ReviewReport
    owned_ids = select(SellerReview.id).where(SellerReview.buyer == buyer.id)
    db.execute(delete(ReviewReport).where(ReviewReport.buyer == buyer.id))
    db.execute(delete(ReviewReport).where(ReviewReport.review_id.in_(owned_ids)))
    db.execute(delete(SellerReview).where(SellerReview.buyer == buyer.id))
    db.execute(delete(BuyerSellerNote).where(BuyerSellerNote.buyer == buyer.id))
    db.delete(buyer)
    db.commit()
    return {'ok': True}
