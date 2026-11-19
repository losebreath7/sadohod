"""Independent staff access, consolidated moderation queue, review decisions.

The seller approval functions are reused unchanged: inventory/pavilion
constraints and concurrent moderation locks remain server-side. Audit entries
are added to the SAME transaction before the existing decision commits.
"""
import hashlib
import re
import secrets
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .account import Buyer, rate_limit
from .admin_auth import require_admin
from .buyer_extras import BuyerMessage
from .buyer_reviews_v082 import ReviewReport, SellerReview, view as review_view
from .database import get_db
from .merchant import (
    review_queue, decide_application, decide_pavilion, decide_product, decide_listing,
    DecisionInput, ProductDecisionInput,
)
from .moderation_models import ModeratorUser, ModeratorSession, ModerationAction
from .models import Seller, Product
from .product_safety import ProductReport, ProductSafetyHold, take_down
from .merchant_models import ShopApplication, PavilionRequest, MerchantProduct, MerchantListing, ShopMembership

router = APIRouter(prefix='/api/v1/moderation', tags=['Moderation'])
admin_router = APIRouter(prefix='/api/v1/admin/moderators',
                         dependencies=[Depends(require_admin)], tags=['Moderation staff'])
bearer = HTTPBearer(auto_error=False)
SESSION_TTL = 8 * 3600


def digest(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def password_hash(password: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    derived = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 260_000)
    return salt + ':' + derived.hex()


def password_ok(password: str, encoded: str) -> bool:
    try:
        salt, expected = encoded.split(':', 1)
        actual = password_hash(password, salt)
        return secrets.compare_digest(actual, encoded)
    except (ValueError, TypeError):
        return False


class LoginInput(BaseModel):
    username: str = Field(min_length=1, max_length=40)
    password: str = Field(min_length=1, max_length=200)


class CreateModerator(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r'^[a-zA-Z0-9._-]+$')
    display_name: str = Field(min_length=2, max_length=80)


class DecisionRequest(BaseModel):
    decision: Literal['approved', 'rejected']
    note: str = Field(default='', max_length=500)
    category: str | None = Field(default=None, max_length=80)


class ReportResolution(BaseModel):
    decision: Literal['hide', 'dismiss']
    note: str = Field(default='', max_length=500)


class ProductTakedownInput(BaseModel):
    reason: str = Field(min_length=5, max_length=500)


class ProductReportDecision(BaseModel):
    decision: Literal['hide', 'dismiss']
    note: str = Field(default='', max_length=500)


class StaffState(BaseModel):
    enabled: bool


def staff_json(m: ModeratorUser):
    return {'id': m.id, 'username': m.username, 'display_name': m.display_name,
            'enabled': m.enabled, 'created_at': m.created_at}


def require_moderator(credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
                      db: Session = Depends(get_db)) -> ModeratorUser:
    if not credentials or credentials.scheme.lower() != 'bearer':
        raise HTTPException(401, 'Требуется вход модератора')
    session = db.get(ModeratorSession, digest(credentials.credentials))
    if session is None or session.expires_at <= time.time():
        raise HTTPException(401, 'Сессия модератора истекла')
    user = db.get(ModeratorUser, session.moderator_id)
    if user is None or not user.enabled:
        raise HTTPException(401, 'Доступ модератора отключён')
    return user


@admin_router.get('')
def list_staff(db: Session = Depends(get_db)):
    return {'items': [staff_json(x) for x in db.scalars(
        select(ModeratorUser).order_by(ModeratorUser.created_at.desc())).all()]}


@admin_router.post('', status_code=201)
def add_staff(body: CreateModerator, db: Session = Depends(get_db)):
    username = body.username.strip().lower()
    if db.scalar(select(ModeratorUser.id).where(ModeratorUser.username == username)):
        raise HTTPException(409, 'Такой логин уже существует')
    password = secrets.token_urlsafe(24)
    staff = ModeratorUser(id=secrets.token_hex(16), username=username,
        display_name=body.display_name.strip(), secret_digest=password_hash(password),
        enabled=True)
    db.add(staff)
    db.commit()
    return {'user': staff_json(staff), 'one_time_password': password}


@admin_router.put('/{moderator_id}')
def set_staff_state(moderator_id: str, body: StaffState, db: Session = Depends(get_db)):
    staff = db.get(ModeratorUser, moderator_id)
    if staff is None:
        raise HTTPException(404, 'Модератор не найден')
    staff.enabled = body.enabled
    if not body.enabled:
        db.execute(delete(ModeratorSession).where(ModeratorSession.moderator_id == staff.id))
    db.commit()
    return {'user': staff_json(staff)}


@admin_router.post('/{moderator_id}/reset-password')
def reset_password(moderator_id: str, db: Session = Depends(get_db)):
    staff = db.get(ModeratorUser, moderator_id)
    if staff is None:
        raise HTTPException(404, 'Модератор не найден')
    password = secrets.token_urlsafe(24)
    staff.secret_digest = password_hash(password)
    db.execute(delete(ModeratorSession).where(ModeratorSession.moderator_id == staff.id))
    db.commit()
    return {'one_time_password': password}


@router.post('/login')
def login(body: LoginInput, request: Request, db: Session = Depends(get_db)):
    username = body.username.strip().lower()
    ip = request.client.host if request.client else 'unknown'
    rate_limit(db, 'mod-login:' + digest(ip + ':' + username)[:36], 8, window=900)
    staff = db.scalar(select(ModeratorUser).where(ModeratorUser.username == username))
    # Equal-work verification so nonexistent accounts aren't trivially probed.
    fake = '00' * 16 + ':' + '00' * 32
    valid = password_ok(body.password, staff.secret_digest if staff else fake)
    if not staff or not staff.enabled or not valid:
        raise HTTPException(401, 'Неверный логин или пароль')
    token = secrets.token_urlsafe(36)
    db.add(ModeratorSession(digest=digest(token), moderator_id=staff.id,
                            expires_at=time.time() + SESSION_TTL))
    db.commit()
    return {'token': token, 'expires_in': SESSION_TTL, 'user': staff_json(staff)}


@router.get('/me')
def me(staff: ModeratorUser = Depends(require_moderator)):
    return {'user': staff_json(staff)}


@router.post('/logout')
def logout(credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
           staff: ModeratorUser = Depends(require_moderator),
           db: Session = Depends(get_db)):
    db.execute(delete(ModeratorSession).where(
        ModeratorSession.digest == digest(credentials.credentials),
        ModeratorSession.moderator_id == staff.id))
    db.commit()
    return {'ok': True}


def record_action(db: Session, staff: ModeratorUser, kind: str, item_id: str,
                  decision: str, note: str):
    db.add(ModerationAction(id=secrets.token_hex(16),
        moderator_id=staff.id, kind=kind, target_id=item_id,
        decision=decision, note=note, created_at=time.time()))


def review_summary(db: Session, review: SellerReview):
    item = review_view(review, db)
    item['photo_count'] = len(item.pop('photos', []))
    seller = db.get(Seller, review.seller)
    item['seller_name'] = seller.name if seller else ''
    return item


def report_json(db: Session, report: ReviewReport):
    review = db.get(SellerReview, report.review_id)
    return {'id': report.id, 'review_id': report.review_id,
            'reason': report.reason, 'created_at': report.created_at,
            'seller_name': (db.get(Seller, review.seller).name
                            if review and db.get(Seller, review.seller) else ''),
            'review': review_summary(db, review) if review else None}


@router.get('/queue')
def queue(staff: ModeratorUser = Depends(require_moderator),
          db: Session = Depends(get_db)):
    data = review_queue(db)
    pending = db.scalars(select(SellerReview).where(
        SellerReview.moderation_status == 'pending',
        SellerReview.hidden.is_(False)).order_by(SellerReview.created_at.desc()).limit(150)).all()
    reports = db.scalars(select(ReviewReport).where(ReviewReport.resolved_at == 0)
        .order_by(ReviewReport.created_at.desc()).limit(150)).all()
    # Never transfer full base64 photos on every 45-second queue poll.
    # Staff loads photos only when opening a specific review/report.
    data['reviews'] = [review_summary(db, r) for r in pending]
    data['reports'] = [report_json(db, r) for r in reports]
    flagged = db.scalars(select(ProductReport).where(
        ProductReport.resolved_at == 0).order_by(
        ProductReport.created_at.desc()).limit(150)).all()
    data['product_reports'] = [product_report_json(db, r) for r in flagged]
    return data


def product_report_json(db: Session, item: ProductReport):
    product = db.get(Product, item.product_id)
    return {'id': item.id, 'product_id': item.product_id,
            'title': product.title if product else '',
            'images': [f'/media/products/{image.filename}'
                       for image in product.images[:12]] if product else [],
            'reason': item.reason, 'created_at': item.created_at}


@router.post('/products/{product_id}/takedown')
def takedown_product(product_id: str, body: ProductTakedownInput,
                     staff: ModeratorUser = Depends(require_moderator),
                     db: Session = Depends(get_db)):
    reason = body.reason.strip()
    if len(reason) < 5:
        raise HTTPException(422, 'Укажите причину снятия товара')
    take_down(db, product_id, staff.id, reason)
    record_action(db, staff, 'products', product_id, 'takedown', reason)
    from .moderation_email import queue_decision
    owner = db.get(MerchantProduct, product_id)
    buyer_id = db.scalar(select(ShopMembership.buyer_id).where(
        ShopMembership.seller_id == owner.seller_id, ShopMembership.role == 'owner')) if owner else None
    buyer = db.get(Buyer, buyer_id) if buyer_id else None
    product = db.get(Product, product_id)
    if buyer:
        queue_decision(db, buyer.email, 'Товар снят с публикации', 'товар', product.title, reason)
    db.commit()
    return {'id': product_id, 'status': 'removed'}


@router.post('/product-reports/{report_id}/resolve')
def resolve_product_report(report_id: str, body: ProductReportDecision,
                           staff: ModeratorUser = Depends(require_moderator),
                           db: Session = Depends(get_db)):
    report = db.get(ProductReport, report_id, with_for_update=True)
    if report is None:
        raise HTTPException(404, 'Жалоба не найдена')
    if report.resolved_at:
        raise HTTPException(409, 'Жалоба уже обработана')
    note = body.note.strip()
    if body.decision == 'hide':
        if len(note) < 5:
            raise HTTPException(422, 'Для снятия товара укажите причину')
        take_down(db, report.product_id, staff.id, note)
    report.resolution = body.decision
    report.resolved_at = time.time()
    record_action(db, staff, 'product_reports', report_id, body.decision, note)
    from .moderation_email import queue_decision
    reporter = db.get(Buyer, report.buyer_id)
    if reporter:
        queue_decision(db, reporter.email, 'Жалоба на товар рассмотрена', 'жалоба', report_id, note or body.decision)
    if body.decision == 'hide':
        owner = db.get(MerchantProduct, report.product_id)
        owner_id = db.scalar(select(ShopMembership.buyer_id).where(
            ShopMembership.seller_id == owner.seller_id,
            ShopMembership.role == 'owner')) if owner else None
        seller_buyer = db.get(Buyer, owner_id) if owner_id else None
        product = db.get(Product, report.product_id)
        if seller_buyer:
            queue_decision(db, seller_buyer.email, 'Товар снят по жалобе', 'товар',
                           product.title if product else report.product_id, note)
    db.commit()
    return {'id': report_id, 'status': body.decision}


@router.get('/reviews/{review_id}')
def review_detail(review_id: str, staff: ModeratorUser = Depends(require_moderator),
                  db: Session = Depends(get_db)):
    row = db.get(SellerReview, review_id)
    if row is None:
        raise HTTPException(404, 'Отзыв не найден')
    return {'item': review_view(row, db)}


@router.get('/reports/{report_id}')
def report_detail(report_id: str, staff: ModeratorUser = Depends(require_moderator),
                  db: Session = Depends(get_db)):
    row = db.get(ReviewReport, report_id)
    if row is None:
        raise HTTPException(404, 'Жалоба не найдена')
    review = db.get(SellerReview, row.review_id)
    return {'item': review_view(review, db) if review else None}


@router.post('/{kind}/{item_id}/decision')
def decide(kind: Literal['applications', 'pavilions', 'products', 'listings', 'reviews'],
           item_id: str, body: DecisionRequest,
           staff: ModeratorUser = Depends(require_moderator),
           db: Session = Depends(get_db)):
    note = body.note.strip()
    if body.decision == 'rejected' and len(note) < 3:
        raise HTTPException(422, 'Укажите причину отклонения (не менее 3 символов)')
    if kind == 'reviews':
        review = db.get(SellerReview, item_id, with_for_update=True)
        if review is None:
            raise HTTPException(404, 'Отзыв не найден')
        if review.moderation_status != 'pending':
            raise HTTPException(409, 'Отзыв уже обработан')
        review.moderation_status = body.decision
        record_action(db, staff, kind, item_id, body.decision, note)
        from .moderation_email import queue_decision
        author = db.get(Buyer, review.buyer)
        if author:
            queue_decision(db, author.email, 'Отзыв рассмотрен модератором', 'отзыв', item_id, note or body.decision)
        db.commit()
        return {'id': item_id, 'status': body.decision}

    if kind == 'products':
        decision_data = ProductDecisionInput(decision=body.decision, note=note,
                                              category=body.category)
    else:
        decision_data = DecisionInput(decision=body.decision, note=note)
    record_action(db, staff, kind, item_id, body.decision, note)
    from .moderation_email import queue_decision
    buyer_id = None
    label = item_id
    if kind == 'applications':
        item = db.get(ShopApplication, item_id)
        buyer_id = item.buyer_id if item else None
        label = item.shop_name if item else item_id
    elif kind == 'pavilions':
        item = db.get(PavilionRequest, item_id)
        buyer_id = db.scalar(select(ShopMembership.buyer_id).where(
            ShopMembership.seller_id == item.seller_id, ShopMembership.role == 'owner')) if item else None
    elif kind in ('products', 'listings'):
        item = db.get(MerchantProduct, item_id) if kind == 'products' else db.get(MerchantListing, item_id)
        buyer_id = db.scalar(select(ShopMembership.buyer_id).where(
            ShopMembership.seller_id == item.seller_id, ShopMembership.role == 'owner')) if item else None
        product = db.get(Product, item_id if kind == 'products' else item.product_id) if item else None
        label = product.title if product else item_id
    buyer = db.get(Buyer, buyer_id) if buyer_id else None
    if buyer:
        queue_decision(db, buyer.email, 'Решение по заявке: ' + body.decision, kind, label, note or body.decision)
    if kind == 'applications':
        return decide_application(item_id, decision_data, db)
    if kind == 'pavilions':
        return decide_pavilion(item_id, decision_data, db)
    if kind == 'products':
        return decide_product(item_id, decision_data, db)
    return decide_listing(item_id, decision_data, db)


@router.post('/reports/{report_id}/resolve')
def resolve_report(report_id: str, body: ReportResolution,
                   staff: ModeratorUser = Depends(require_moderator),
                   db: Session = Depends(get_db)):
    report = db.get(ReviewReport, report_id, with_for_update=True)
    if report is None:
        raise HTTPException(404, 'Жалоба не найдена')
    if report.resolved_at:
        raise HTTPException(409, 'Жалоба уже обработана')
    review = db.get(SellerReview, report.review_id)
    if body.decision == 'hide':
        if review is not None:
            review.hidden = True
    report.resolution = body.decision
    report.resolved_at = time.time()
    record_action(db, staff, 'reports', report_id, body.decision, body.note.strip())
    from .moderation_email import queue_decision
    reporter = db.get(Buyer, report.buyer)
    if reporter:
        queue_decision(db, reporter.email, 'Жалоба на отзыв рассмотрена', 'жалоба', report_id, body.note.strip() or body.decision)
    if body.decision == 'hide' and review is not None:
        author = db.get(Buyer, review.buyer)
        if author:
            queue_decision(db, author.email, 'Отзыв скрыт по жалобе',
                           'отзыв', review.id, body.note.strip() or 'Решение модерации')
    db.commit()
    return {'id': report_id, 'status': body.decision}


@router.get('/history')
def history(staff: ModeratorUser = Depends(require_moderator),
            db: Session = Depends(get_db)):
    records = db.scalars(select(ModerationAction)
        .order_by(ModerationAction.created_at.desc()).limit(100)).all()
    return {'items': [{
        'id': x.id, 'kind': x.kind, 'target_id': x.target_id,
        'decision': x.decision, 'note': x.note, 'created_at': x.created_at,
        'moderator': (db.get(ModeratorUser, x.moderator_id).display_name
                      if db.get(ModeratorUser, x.moderator_id) else 'Модератор')
    } for x in records]}


@router.get('/chats')
def chats(staff: ModeratorUser = Depends(require_moderator),
          db: Session = Depends(get_db)):
    # Text-only triage. Replies remain in the established Telegram workflow.
    messages = db.scalars(select(BuyerMessage).order_by(
        BuyerMessage.sent.desc()).limit(500)).all()
    seen = set()
    threads = []
    for m in messages:
        key = (m.buyer, m.kind)
        if key in seen:
            continue
        seen.add(key)
        buyer = db.get(Buyer, m.buyer)
        threads.append({'buyer_id': m.buyer, 'kind': m.kind,
            'name': buyer.name if buyer else '', 'email': buyer.email if buyer else '',
            'last_message': m.text[:180], 'sent': m.sent, 'staff': m.staff})
    return {'items': threads[:100]}


@router.get('/chats/{buyer_id}/{kind}')
def chat_thread(buyer_id: str,
                kind: Literal['support', 'cooperation', 'm_support', 'm_cooperation'],
                staff: ModeratorUser = Depends(require_moderator),
                db: Session = Depends(get_db)):
    if db.get(Buyer, buyer_id) is None:
        raise HTTPException(404, 'Диалог не найден')
    messages = db.scalars(select(BuyerMessage).where(
        BuyerMessage.buyer == buyer_id, BuyerMessage.kind == kind)
        .order_by(BuyerMessage.sent.desc()).limit(100)).all()
    return {'items': [{'id': m.id, 'text': m.text, 'sent': m.sent,
                       'staff': m.staff} for m in reversed(messages)]}
