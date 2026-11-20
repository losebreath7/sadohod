"""Seller onboarding and moderated product distribution (v0.8.0).

All merchant access derives from the buyer's verified email session. An approved
shop may have multiple claimed physical pavilions. Unreviewed photos/products
and offers are never exposed in the public catalog.
"""
import hashlib
import re
import secrets
import time
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .account import Buyer, current_buyer
from .admin import upload_images
from .admin_auth import require_admin
from .database import get_db
from .product_categories import resolve_category, is_unassigned
from .category_inference import assign_category, mark_manual, describe
from .models import (Offer, OfferSaleModes, Pavilion, Product, ProductDetails,
                     Seller, SellerDetails)
from .merchant_models import (MerchantInvitation, MerchantListing, MerchantProduct, MerchantOperation, PavilionClaim,
                              PavilionRequest, ShopApplication, ShopMembership, ShopRecord)

router = APIRouter(prefix='/api/v1/merchant', tags=['Merchant'])
admin_router = APIRouter(prefix='/api/v1/admin/merchant', dependencies=[Depends(require_admin)], tags=['Merchant moderation'])


def uid(prefix):
    return prefix + uuid.uuid4().hex[:24]


def key(value):
    return ' '.join(value.casefold().split())


class ApplyInput(BaseModel):
    shop_name: str = Field(min_length=2, max_length=120)
    contact: str = Field(default='', max_length=250)
    zone: str = Field(min_length=1, max_length=160)
    code: str = Field(min_length=1, max_length=32)

    @field_validator('shop_name', 'contact', 'zone', 'code')
    @classmethod
    def tidy(cls, value):
        return value.strip()


class PavilionInput(BaseModel):
    zone: str = Field(min_length=1, max_length=160)
    code: str = Field(min_length=1, max_length=32)

    @field_validator('zone', 'code')
    @classmethod
    def tidy(cls, value):
        return value.strip()


class DraftProductInput(BaseModel):
    request_id: str | None = Field(default=None, min_length=8, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    title: str = Field(default='', max_length=160)
    category: str = Field(default='', max_length=80)
    description: str = Field(default='', max_length=5000)
    colors: list[str] = Field(default_factory=list, max_length=30)
    sizes: list[str] = Field(default_factory=list, max_length=30)


class ListingInput(BaseModel):
    pavilion_id: str = Field(min_length=1, max_length=32)
    price: int | None = Field(default=None, ge=0, le=100000000, strict=True)
    sale_modes: list[Literal['wholesale', 'retail']] = Field(min_length=1, max_length=2)

    @field_validator('sale_modes')
    @classmethod
    def dedupe(cls, value):
        if len(value) != len(set(value)):
            raise ValueError('Повторяющиеся способы продажи')
        return value


class DecisionInput(BaseModel):
    decision: Literal['approved', 'rejected']
    note: str = Field(default='', max_length=500)


class ProductDecisionInput(DecisionInput):
    category: str | None = Field(default=None, max_length=80)


class InvitationInput(ApplyInput):
    email: str = Field(max_length=254)

    @field_validator('email')
    @classmethod
    def email_normalized(cls, value):
        clean = value.strip().lower()
        if not clean or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', clean):
            raise ValueError('Некорректный email')
        return clean


class AcceptInvitation(BaseModel):
    token: str = Field(min_length=12, max_length=250)


class ShopEditInput(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    contact: str = Field(default='', max_length=250)


def shop_for(buyer: Buyer, db: Session) -> Seller:
    membership = db.scalar(select(ShopMembership).where(ShopMembership.buyer_id == buyer.id, ShopMembership.role == 'owner'))
    shop = db.scalar(select(Seller).where(Seller.id == membership.seller_id).with_for_update(of=Seller)) if membership else None
    if shop is None or db.get(ShopRecord, shop.id) is None:
        raise HTTPException(403, 'Для этого действия необходим подтверждённый кабинет продавца.')
    from .moderation_enforcement import require_shop_allowed
    require_shop_allowed(db, shop.id)
    return shop


def merchant_product(pid: str, shop: Seller, db: Session):
    owner = db.get(MerchantProduct, pid)
    if owner is None or owner.seller_id != shop.id or owner.status == 'deleted':
        raise HTTPException(404, 'Товар не найден в вашем магазине.')
    return owner


def check_pavilion(db, zone, code):
    zk, ck = key(zone), key(code)
    if not zk or not ck:
        raise HTTPException(422, 'Укажите сектор и номер павильона.')
    if db.get(PavilionClaim, (zk, ck)) is not None:
        raise HTTPException(409, 'Этот павильон уже закреплён за продавцом.')
    # Legacy pavilion records have no normalized key columns; check them before
    # granting a new claim, rather than rewriting old marketplace data.
    for p in db.scalars(select(Pavilion)).all():
        if key(p.zone) == zk and key(p.code) == ck:
            raise HTTPException(409, 'Павильон уже зарегистрирован в каталоге.')
    return zk, ck


def add_claim(db, shop_id, zone, code, pavilion_id):
    zk, ck = key(zone), key(code)
    db.add(PavilionClaim(zone_key=zk, code_key=ck, seller_id=shop_id, pavilion_id=pavilion_id))


def safe_commit(db):
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, 'Конфликт данных. Обновите страницу и повторите действие.') from exc


def listing_for(lid: str, shop: Seller, db: Session):
    row = db.get(MerchantListing, lid)
    if row is None or row.seller_id != shop.id:
        raise HTTPException(404, 'Предложение не найдено в вашем магазине.')
    return row


def as_listing(db, row):
    pavilion = db.get(Pavilion, row.pavilion_id)
    return {'id': row.id, 'product_id': row.product_id, 'pavilion_id': row.pavilion_id,
            'pavilion': {'zone': pavilion.zone, 'code': pavilion.code} if pavilion else None,
            'price': row.price, 'sale_modes': (['wholesale'] if row.wholesale else []) + (['retail'] if row.retail else []),
            'status': row.status, 'note': row.note, 'published': row.offer_id is not None}


def as_product(db, owner):
    p = db.get(Product, owner.product_id)
    if not p:
        raise HTTPException(404, 'Товар не найден.')
    return {'id': p.id, 'title': p.title, 'category': p.category, 'description': p.description,
            'category_inference': describe(db, p),
            'image_items': [{'id': img.id, 'url': f'/media/products/{img.filename}'} for img in sorted(p.images, key=lambda i: (i.ordering.position if i.ordering else 0, i.id))],
            'colors': p.colors, 'sizes': p.details.sizes if p.details else [],
            'status': owner.status, 'note': owner.note,
            'images': [f'/media/products/{img.filename}' for img in sorted(p.images,key=lambda i: (i.ordering.position if i.ordering else 0, i.id))],
            'listings': [as_listing(db, row) for row in db.scalars(select(MerchantListing).where(MerchantListing.product_id == p.id)).all()]}


def as_application(row):
    return {'id': row.id, 'shop_name': row.shop_name, 'contact': row.contact,
            'zone': row.zone, 'code': row.code, 'status': row.status,
            'note': row.note, 'seller_id': row.seller_id}


@router.get('/me')
def me(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    applications = db.scalars(select(ShopApplication).where(ShopApplication.buyer_id == buyer.id).order_by(ShopApplication.created_at.desc())).all()
    membership = db.scalar(select(ShopMembership).where(ShopMembership.buyer_id == buyer.id, ShopMembership.role == 'owner'))
    seller = db.get(Seller, membership.seller_id) if membership else None
    return {'email': buyer.email, 'shop': {'id': seller.id, 'name': seller.name, 'contact': seller.details.contact if seller.details else ''} if seller else None,
            'applications': [as_application(r) for r in applications]}


@router.post('/applications', status_code=201)
def apply(data: ApplyInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.scalar(select(Buyer).where(Buyer.id == buyer.id).with_for_update())
    existing = db.scalar(select(ShopMembership).where(ShopMembership.buyer_id == buyer.id))
    if existing:
        raise HTTPException(409, 'У вас уже есть подтверждённый магазин.')
    pending = db.scalar(select(ShopApplication).where(ShopApplication.buyer_id == buyer.id, ShopApplication.status == 'pending'))
    if pending:
        if all(key(getattr(pending, f)) == key(getattr(data, f)) for f in ('zone', 'code', 'shop_name', 'contact')):
            return as_application(pending)
        raise HTTPException(409, 'Ваша заявка уже находится на проверке.')
    check_pavilion(db, data.zone, data.code)
    application = ShopApplication(id=uid('a-'), buyer_id=buyer.id, shop_name=data.shop_name, contact=data.contact,
                                  zone=data.zone, code=data.code, status='pending')
    db.add(application); safe_commit(db)
    return as_application(application)


@router.put('/applications/{aid}')
def resubmit_application(aid: str, data: ApplyInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.scalar(select(Buyer).where(Buyer.id == buyer.id).with_for_update())
    row = db.scalar(select(ShopApplication).where(ShopApplication.id == aid,
        ShopApplication.buyer_id == buyer.id).with_for_update())
    if row is None:
        raise HTTPException(404, 'Заявка не найдена.')
    if db.get(ShopMembership, buyer.id):
        raise HTTPException(409, 'Магазин уже подтверждён. Обновите список магазинов.')
    fields = ('zone', 'code', 'shop_name', 'contact')
    if row.status == 'pending' and all(key(getattr(row, f)) == key(getattr(data, f)) for f in fields):
        return as_application(row)
    if row.status != 'rejected':
        raise HTTPException(409, 'Можно исправить только отклонённую заявку. Обновите её статус.')
    if db.scalar(select(ShopApplication.id).where(ShopApplication.buyer_id == buyer.id,
            ShopApplication.status == 'pending', ShopApplication.id != aid)):
        raise HTTPException(409, 'Другая заявка уже находится на проверке.')
    check_pavilion(db, data.zone, data.code)
    for field in fields:
        setattr(row, field, getattr(data, field))
    row.status, row.note = 'pending', ''
    safe_commit(db)
    return as_application(row)


@router.post('/invitations/accept', status_code=201)
def accept_invitation(body: AcceptInvitation, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    token_digest = hashlib.sha256(body.token.encode()).hexdigest()
    invitation = db.scalar(select(MerchantInvitation).where(MerchantInvitation.code_digest == token_digest))
    if not invitation or invitation.used_at is not None or invitation.expires_at < time.time():
        raise HTTPException(400, 'Приглашение недействительно или срок его действия истёк.')
    if invitation.email != buyer.email:
        raise HTTPException(403, 'Приглашение предназначено для другого email.')
    if db.scalar(select(ShopMembership).where(ShopMembership.buyer_id == buyer.id)):
        raise HTTPException(409, 'У аккаунта уже есть магазин.')
    check_pavilion(db, invitation.zone, invitation.code)
    seller_id, pavilion_id = uid('s-'), uid('v-')
    db.add(Pavilion(id=pavilion_id, zone=invitation.zone, code=invitation.code))
    db.add(Seller(id=seller_id, name=invitation.shop_name, pavilion_id=pavilion_id,
                  details=SellerDetails(contact=invitation.contact, is_demo=False)))
    db.flush()
    db.add(ShopRecord(seller_id=seller_id))
    db.add(ShopMembership(buyer_id=buyer.id, seller_id=seller_id, role='owner'))
    add_claim(db, seller_id, invitation.zone, invitation.code, pavilion_id)
    invitation.used_at = time.time()
    # A now-confirmed invitation supersedes pending applications of this buyer.
    for application in db.scalars(select(ShopApplication).where(ShopApplication.buyer_id == buyer.id, ShopApplication.status == 'pending')):
        application.status = 'rejected'; application.note = 'Магазин активирован по приглашению.'
    safe_commit(db)
    return {'id': seller_id, 'name': invitation.shop_name}


@router.get('/shop')
def shop(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    return {'id': seller.id, 'name': seller.name, 'contact': seller.details.contact if seller.details else ''}


@router.put('/shop')
def edit_shop(data: ShopEditInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    seller.name = data.name.strip()
    if seller.details is None:
        seller.details = SellerDetails(contact=data.contact.strip(), is_demo=False)
    else:
        seller.details.contact = data.contact.strip()
    safe_commit(db)
    return {'id': seller.id, 'name': seller.name, 'contact': seller.details.contact}


@router.get('/pavilions')
def pavilions(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    claims = db.scalars(select(PavilionClaim).where(PavilionClaim.seller_id == seller.id)).all()
    requests = db.scalars(select(PavilionRequest).where(PavilionRequest.seller_id == seller.id, PavilionRequest.status != 'approved')).all()
    return {'items': [{'id': c.pavilion_id, 'zone': db.get(Pavilion, c.pavilion_id).zone,
                       'code': db.get(Pavilion, c.pavilion_id).code, 'status': 'approved'} for c in claims],
            'requests': [{'id': r.id, 'zone': r.zone, 'code': r.code, 'status': r.status, 'note': r.note} for r in requests]}


@router.post('/pavilions', status_code=201)
def request_pavilion(data: PavilionInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    db.scalar(select(Seller).where(Seller.id == seller.id).with_for_update(of=Seller))
    check_pavilion(db, data.zone, data.code)
    for r in db.scalars(select(PavilionRequest).where(PavilionRequest.seller_id == seller.id, PavilionRequest.status == 'pending')):
        if key(r.zone) == key(data.zone) and key(r.code) == key(data.code):
            return {'id': r.id, 'status': r.status}
    request = PavilionRequest(id=uid('r-'), seller_id=seller.id, zone=data.zone, code=data.code, status='pending')
    db.add(request); safe_commit(db)
    return {'id': request.id, 'status': request.status}


@router.put('/pavilions/requests/{rid}')
def resubmit_pavilion(rid: str, data: PavilionInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    db.scalar(select(Seller).where(Seller.id == seller.id).with_for_update(of=Seller))
    row = db.scalar(select(PavilionRequest).where(PavilionRequest.id == rid,
        PavilionRequest.seller_id == seller.id).with_for_update())
    if row is None:
        raise HTTPException(404, 'Заявка на павильон не найдена.')
    if row.status == 'pending' and key(row.zone) == key(data.zone) and key(row.code) == key(data.code):
        return {'id': row.id, 'zone': row.zone, 'code': row.code, 'status': row.status, 'note': row.note}
    if row.status != 'rejected':
        raise HTTPException(409, 'Можно исправить только отклонённую заявку. Обновите её статус.')
    check_pavilion(db, data.zone, data.code)
    for other in db.scalars(select(PavilionRequest).where(PavilionRequest.seller_id == seller.id,
            PavilionRequest.status == 'pending', PavilionRequest.id != rid)):
        if key(other.zone) == key(data.zone) and key(other.code) == key(data.code):
            raise HTTPException(409, 'Этот павильон уже отправлен на проверку.')
    row.zone, row.code, row.status, row.note = data.zone, data.code, 'pending', ''
    safe_commit(db)
    return {'id': row.id, 'zone': row.zone, 'code': row.code, 'status': row.status, 'note': row.note}


@router.get('/products')
def products(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    owners = db.scalars(select(MerchantProduct).where(MerchantProduct.seller_id == seller.id, MerchantProduct.status != 'deleted').order_by(MerchantProduct.created_at.desc())).all()
    return {'items': [as_product(db, p) for p in owners]}


@router.post('/products', status_code=201)
def add_product(data: DraftProductInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    if data.request_id:
        old = db.get(MerchantOperation, (seller.id, data.request_id))
        if old:
            if old.digest != 'create-product':
                raise HTTPException(409, 'Ключ запроса уже использован.')
            return as_product(db, merchant_product(old.result['id'], seller, db))
    p = Product(id=uid('u-'), title=data.title.strip() or 'Без названия', category=data.category.strip() or 'Без категории', description=data.description.strip(),
                colors=data.colors, is_demo=False, details=ProductDetails(active=False, sizes=data.sizes))
    db.add(p)
    db.flush()
    assign_category(db, p)
    db.add(MerchantProduct(product_id=p.id, seller_id=seller.id, status='draft'))
    if data.request_id:
        db.add(MerchantOperation(seller_id=seller.id, request_id=data.request_id, digest='create-product', result={'id': p.id}))
    safe_commit(db)
    return as_product(db, db.get(MerchantProduct, p.id))


@router.get('/products/{pid}')
def product(pid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    return as_product(db, merchant_product(pid, seller, db))


@router.put('/products/{pid}')
def edit_product(pid: str, data: DraftProductInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    owner = merchant_product(pid, seller, db)
    if owner.status == 'pending':
        raise HTTPException(409, 'Товар на модерации. Дождитесь решения.')
    p = db.get(Product, pid)
    p.title = data.title.strip() or 'Без названия'; p.category = data.category.strip() or 'Без категории'; p.description = data.description.strip()
    p.colors = data.colors
    p.details.sizes = data.sizes
    # An approved product stays live while its metadata is edited.
    # Existing offers are not removed or re-queued for manual review.
    if owner.status != 'approved':
        owner.status = 'draft'
    owner.note = ''
    assign_category(db, p)
    if owner.status == 'approved':
        from .product_screening import assess, hold_for_review
        reason = assess(db, p)
        if reason:
            hold_for_review(db, owner, p, reason)
    safe_commit(db)
    return as_product(db, owner)


@router.post('/products/{pid}/images', status_code=201)
def product_images(pid: str, files: list[UploadFile] = File(...), request_id: str | None = Form(default=None, min_length=8, max_length=80, pattern=r'^[a-zA-Z0-9_-]+$'), replace_id: str | None = Form(default=None, max_length=32), buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    owner = merchant_product(pid, seller, db)
    if not 1 <= len(files) <= 6:
        raise HTTPException(422, 'За раз можно загрузить от 1 до 6 фотографий.')
    if request_id:
        digest = hashlib.sha256((pid + ':' + (replace_id or '')).encode())
        for f in files:
            digest.update(f.filename.encode() if f.filename else b'')
            content = f.file.read(8 * 1024 * 1024 + 1)
            if len(content) > 8 * 1024 * 1024:
                raise HTTPException(413, 'Каждая фотография должна быть не больше 8 МБ.')
            digest.update(content)
            f.file.seek(0)
        fingerprint = digest.hexdigest()
        old = db.get(MerchantOperation, (seller.id, request_id))
        if old:
            for f in files: f.file.close()
            if old.digest != fingerprint:
                raise HTTPException(409, 'Фотографии изменились: нужен новый ключ запроса.')
            return as_product(db, owner)
        db.add(MerchantOperation(seller_id=seller.id, request_id=request_id, digest=fingerprint, result={'id': pid}))
    if owner.status not in ('draft', 'rejected', 'approved'):
        raise HTTPException(409, 'Товар сейчас недоступен для изменения фотографий.')
    # Seller catalogue: at most six images after a new upload or replacement.
    # Keep the idempotent retry lookup above this check so a successful
    # repeated request does not fail once the product has six images.
    current_count = len(db.get(Product, owner.product_id).images)
    if current_count + len(files) - (1 if replace_id else 0) > 6:
        raise HTTPException(422, 'На товар можно добавить не больше 6 фотографий.')
    # Stage a moderation hold in the same transaction as the new photo
    # records. The shared uploader commits both atomically; there is never
    # a committed, publicly visible unreviewed photo.
    was_approved = owner.status == 'approved'
    if was_approved:
        from .product_screening import hold_for_review
        hold_for_review(db, owner, db.get(Product, pid),
                        'Автопроверка: фотография обновлена, проверка ожидается')
    replaced_filename = None
    if replace_id:
        from sqlalchemy import delete, text
        from .models import ProductImage, ImageMLEmbedding
        image = db.get(ProductImage, replace_id)
        if image is None or image.product_id != pid or len(files) != 1:
            raise HTTPException(422, 'Для замены нужна одна фотография этого товара.')
        replaced_filename = image.filename
        db.execute(delete(ImageMLEmbedding).where(ImageMLEmbedding.image_id == replace_id))
        if db.bind.dialect.name == 'postgresql':
            for table in ('product_image_vectors', 'product_image_ml_vectors'):
                db.execute(text(f'DELETE FROM {table} WHERE image_id=:id'), {'id': replace_id})
        db.delete(image)
        db.flush()
        db.expire(db.get(Product, pid), ['images'])
    # The legacy admin uploader already provides image safety, deduped filenames,
    # ML indexing and transaction/filename cleanup on failure.
    upload_images(pid, files, db)
    if replaced_filename and replaced_filename.startswith('uploads/'):
        from . import admin
        try:
            (admin.MEDIA / replaced_filename).unlink(missing_ok=True)
        except OSError:
            pass  # DB replacement succeeded; deferred file cleanup is non-critical.
    db.expire_all()
    # The shared uploader commits its file transaction. Reacquire the seller lock
    # before classification; another request may already have submitted the draft.
    shop_for(buyer, db)
    owner = merchant_product(pid, seller, db)
    if owner.status in ('draft', 'rejected', 'pending', 'approved'):
        product = db.get(Product, pid)
        assign_category(db, product)
        if was_approved:
            from .product_screening import assess
            reason = assess(db, product)
            rows = db.scalars(select(MerchantListing).where(
                MerchantListing.product_id == pid)).all()
            if reason:
                owner.note = reason
                for row in rows:
                    if row.status == 'pending':
                        row.note = reason
            else:
                # Only a successful visual check may restore previously
                # published listings after the atomic image replacement.
                for row in rows:
                    if row.status == 'pending':
                        publish_listing(db, row, screened=True)
                owner.status = 'approved'
                owner.note = ''
                product.details.active = any(row.offer_id is not None for row in rows)
        safe_commit(db)
    return as_product(db, merchant_product(pid, seller, db))


@router.post('/products/{pid}/listings', status_code=201)
def add_listing(pid: str, data: ListingInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    owner = merchant_product(pid, seller, db)
    claim = db.scalar(select(PavilionClaim).where(PavilionClaim.pavilion_id == data.pavilion_id, PavilionClaim.seller_id == seller.id))
    if claim is None:
        raise HTTPException(403, 'Павильон не подтверждён для вашего магазина.')
    existing = db.scalar(select(MerchantListing).where(MerchantListing.product_id == pid, MerchantListing.pavilion_id == data.pavilion_id))
    if existing:
        raise HTTPException(409, 'Товар уже распределён в этот павильон.')
    if owner.status == 'pending':
        raise HTTPException(409, 'Дождитесь завершения модерации товара.')
    row = MerchantListing(id=uid('l-'), product_id=pid, seller_id=seller.id,
                          pavilion_id=data.pavilion_id, price=data.price,
                          wholesale='wholesale' in data.sale_modes, retail='retail' in data.sale_modes,
                          status='approved' if owner.status == 'approved' else 'draft')
    db.add(row)
    if owner.status == 'approved':
        publish_listing(db, row)
        db.get(Product, pid).details.active = True
    safe_commit(db)
    return as_listing(db, row)


@router.put('/listings/{lid}')
def edit_listing(lid: str, data: ListingInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    row = listing_for(lid, seller, db)
    if row.pavilion_id != data.pavilion_id:
        raise HTTPException(409, 'Изменить павильон предложения нельзя. Создайте отдельное предложение.')
    owner = merchant_product(row.product_id, seller, db)
    if owner.status == 'pending' or row.status == 'pending':
        raise HTTPException(409, 'Предложение на модерации.')
    row.price = data.price; row.wholesale = 'wholesale' in data.sale_modes; row.retail = 'retail' in data.sale_modes
    # Published and paused placements retain visibility when their price changes.
    if owner.status == 'approved' and row.status != 'paused':
        publish_listing(db, row)
    elif owner.status != 'approved':
        row.status = 'draft'
    row.note = ''
    safe_commit(db)
    return as_listing(db, row)


@router.post('/listings/{lid}/pause')
def pause_listing(lid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    row = listing_for(lid, seller, db)
    if row.status == 'paused':
        return as_listing(db, row)
    if row.status not in ('approved', 'pending') or row.offer_id is None:
        raise HTTPException(409, 'Снять с продажи можно только ранее опубликованное предложение.')
    if row.offer_id:
        offer = db.get(Offer, row.offer_id)
        row.offer_id = None
        db.flush()
        if offer: db.delete(offer)
    row.status = 'paused'
    p = db.get(Product, row.product_id)
    # Pause must only affect this product, not other merchant products.
    if p and not db.scalar(select(MerchantListing.id).where(MerchantListing.product_id == p.id,
                               MerchantListing.id != row.id, MerchantListing.offer_id.is_not(None))):
        p.details.active = False
    safe_commit(db)
    return as_listing(db, row)


@router.post('/listings/{lid}/resume')
def resume_listing(lid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    row = listing_for(lid, seller, db)
    owner = merchant_product(row.product_id, seller, db)
    if row.status != 'paused' or owner.status != 'approved':
        raise HTTPException(409, 'Возобновить можно только предложение одобренного товара.')
    publish_listing(db, row)
    db.get(Product, row.product_id).details.active = True
    safe_commit(db)
    return as_listing(db, row)


@router.post('/products/{pid}/submit')
def submit_product(pid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    seller = shop_for(buyer, db)
    owner = merchant_product(pid, seller, db)
    if owner.status not in ('draft', 'rejected'):
        raise HTTPException(409, 'Товар уже отправлен или опубликован.')
    from .product_safety import require_publishable
    require_publishable(db, pid)
    p = db.get(Product, pid)
    if not p.images:
        raise HTTPException(409, 'Добавьте хотя бы одну фотографию.')
    rows = db.scalars(select(MerchantListing).where(MerchantListing.product_id == pid)).all()
    if not rows:
        raise HTTPException(409, 'Выберите хотя бы один подтверждённый павильон.')
    if not any(r.status in ('draft', 'pending', 'approved', 'rejected') for r in rows):
        raise HTTPException(409, 'Нет доступных предложений для публикации.')
    from .product_screening import assess, hold_for_review
    reason = assess(db, p)
    if reason:
        hold_for_review(db, owner, p, reason)
    else:
        for r in rows:
            if r.status in ('draft', 'rejected'):
                publish_listing(db, r, screened=True)
        owner.status = 'approved'
        owner.note = ''
        p.details.active = any(r.offer_id is not None for r in rows)
    safe_commit(db)
    return as_product(db, owner)


# ----------------------- Admin moderation -----------------------
@admin_router.post('/invitations', status_code=201)
def create_invitation(data: InvitationInput, db: Session = Depends(get_db)):
    check_pavilion(db, data.zone, data.code)
    token = secrets.token_urlsafe(32)
    invitation = MerchantInvitation(id=uid('n-'), code_digest=hashlib.sha256(token.encode()).hexdigest(),
                                    email=data.email, shop_name=data.shop_name, contact=data.contact,
                                    zone=data.zone, code=data.code, expires_at=time.time()+7*86400)
    db.add(invitation); safe_commit(db)
    # Token is only returned to the admin once; only its digest is saved.
    return {'id': invitation.id, 'invite_token': token, 'expires_in': 7*86400}


@admin_router.get('/queue')
def review_queue(db: Session = Depends(get_db)):
    applications = db.scalars(select(ShopApplication).where(ShopApplication.status == 'pending')).all()
    pavilion_requests = db.scalars(select(PavilionRequest).where(PavilionRequest.status == 'pending')).all()
    products = db.scalars(select(MerchantProduct).where(MerchantProduct.status == 'pending')).all()
    new_listings = db.scalars(select(MerchantListing).where(MerchantListing.status == 'pending')).all()
    return {'applications': [{**as_application(x), 'email': db.get(Buyer, x.buyer_id).email if db.get(Buyer, x.buyer_id) else None} for x in applications],
            'pavilions': [{'id': r.id, 'seller_id': r.seller_id, 'zone': r.zone, 'code': r.code} for r in pavilion_requests],
            'products': [as_product(db, p) for p in products],
            'listings': [as_listing(db, row) for row in new_listings]}


@admin_router.post('/applications/{aid}/decision')
def decide_application(aid: str, body: DecisionInput, db: Session = Depends(get_db)):
    application = db.get(ShopApplication, aid)
    if not application:
        raise HTTPException(404, 'Заявка не найдена.')
    db.scalar(select(Buyer).where(Buyer.id == application.buyer_id).with_for_update())
    db.refresh(application, with_for_update=True)
    if application.status != 'pending':
        raise HTTPException(409, 'Заявка уже обработана.')
    if body.decision == 'approved':
        # Re-check on approval to close races with other applications/admin imports.
        check_pavilion(db, application.zone, application.code)
        if db.scalar(select(ShopMembership).where(ShopMembership.buyer_id == application.buyer_id)):
            raise HTTPException(409, 'У заявителя уже есть магазин.')
        sid, pid = uid('s-'), uid('v-')
        db.add(Pavilion(id=pid, zone=application.zone, code=application.code))
        db.add(Seller(id=sid, name=application.shop_name, pavilion_id=pid,
                      details=SellerDetails(contact=application.contact, is_demo=False)))
        db.flush()
        db.add(ShopRecord(seller_id=sid))
        db.add(ShopMembership(buyer_id=application.buyer_id, seller_id=sid, role='owner'))
        add_claim(db, sid, application.zone, application.code, pid)
        application.seller_id = sid
    application.status = body.decision
    application.note = body.note
    safe_commit(db)
    return as_application(application)


@admin_router.post('/pavilions/{rid}/decision')
def decide_pavilion(rid: str, body: DecisionInput, db: Session = Depends(get_db)):
    request = db.get(PavilionRequest, rid)
    if not request:
        raise HTTPException(404, 'Заявка на павильон не найдена.')
    db.scalar(select(Seller).where(Seller.id == request.seller_id).with_for_update(of=Seller))
    db.refresh(request, with_for_update=True)
    if request.status != 'pending':
        raise HTTPException(409, 'Заявка уже обработана.')
    if body.decision == 'approved':
        if db.get(ShopRecord, request.seller_id) is None:
            raise HTTPException(409, 'Магазин не подтверждён.')
        check_pavilion(db, request.zone, request.code)
        pid = uid('v-')
        db.add(Pavilion(id=pid, zone=request.zone, code=request.code))
        db.flush()
        add_claim(db, request.seller_id, request.zone, request.code, pid)
    request.status = body.decision; request.note = body.note
    safe_commit(db)
    return {'id': request.id, 'status': request.status}


def publish_listing(db, row, *, screened=False, moderator_approved=False):
    from .product_safety import require_publishable
    require_publishable(db, row.product_id)
    from .moderation_enforcement import require_shop_allowed
    require_shop_allowed(db, row.seller_id)
    # The final Offer creation point is shared by save, submit, resume,
    # move, copy and staff decisions. Never trust a listing status alone.
    owner = db.get(MerchantProduct, row.product_id)
    if owner is None or not (owner.status == 'approved' or screened or moderator_approved):
        raise HTTPException(409, 'Товар должен пройти проверку перед публикацией.')
    claim = db.scalar(select(PavilionClaim).where(PavilionClaim.pavilion_id == row.pavilion_id, PavilionClaim.seller_id == row.seller_id))
    if not claim:
        raise HTTPException(409, 'Павильон больше не закреплён за продавцом.')
    if not (row.wholesale or row.retail):
        raise HTTPException(409, 'Укажите опт и/или розницу.')
    p = db.get(Product, row.product_id)
    if p is None or not p.images:
        raise HTTPException(409, 'Без изображения публиковать нельзя.')
    # Category inference is advisory; missing category must not block an
    # approved seller's publication. Content screening will be separate.
    if row.offer_id:
        offer = db.get(Offer, row.offer_id)
        if not offer:
            raise HTTPException(409, 'Не найдено ранее опубликованное предложение.')
        offer.price = row.price
        if offer.modes is None: offer.modes = OfferSaleModes()
        offer.modes.wholesale = row.wholesale; offer.modes.retail = row.retail
    else:
        offer = Offer(id=uid('o-'), product_id=row.product_id, seller_id=row.seller_id,
                      pavilion_id=row.pavilion_id, price=row.price,
                      modes=OfferSaleModes(wholesale=row.wholesale, retail=row.retail))
        db.add(offer)
        db.flush()  # FK target must exist before assigning merchant_listings.offer_id.
        row.offer_id = offer.id
    row.status = 'approved'; row.note = ''


@admin_router.post('/products/{pid}/decision')
def decide_product(pid: str, body: ProductDecisionInput, db: Session = Depends(get_db)):
    owner = db.get(MerchantProduct, pid)
    if owner is None: raise HTTPException(404, 'Товар не найден.')
    db.scalar(select(Seller).where(Seller.id == owner.seller_id).with_for_update(of=Seller))
    db.refresh(owner)
    if owner.status != 'pending': raise HTTPException(409, 'Товар не ожидает модерации.')
    # publish_listing() has an intermediate flush before owner.status changes.
    # This moderator decision owns all placement transitions in the transaction;
    # one product notification must replace duplicate placement notices.
    db.info.setdefault('_seller_notified_product_ids', set()).add(pid)
    p = db.get(Product, pid)
    if body.decision == 'approved':
        category = body.category.strip() if body.category is not None else p.category
        if is_unassigned(category):
            raise HTTPException(409, 'Укажите категорию товара перед публикацией.')
        p.category = category
        if body.category is not None:
            mark_manual(db, p)
        if not p.images:
            raise HTTPException(409, 'Нельзя публиковать товар без фотографии.')
        rows = db.scalars(select(MerchantListing).where(MerchantListing.product_id == pid, MerchantListing.status.in_(['pending','approved','paused']))).all()
        if not rows:
            raise HTTPException(409, 'Нельзя публиковать товар без доступных предложений.')
        for row in rows:
            if row.status == 'pending': publish_listing(db, row, moderator_approved=True)
        p.details.active = any(row.offer_id is not None for row in rows)
    else:
        p.details.active = False
        for row in db.scalars(select(MerchantListing).where(MerchantListing.product_id == pid, MerchantListing.status == 'pending')):
            row.status = 'rejected'; row.note = body.note
    owner.status = body.decision; owner.note = body.note
    safe_commit(db)
    return as_product(db, owner)


@admin_router.post('/listings/{lid}/decision')
def decide_listing(lid: str, body: DecisionInput, db: Session = Depends(get_db)):
    row = db.get(MerchantListing, lid)
    if row is None: raise HTTPException(404, 'Предложение не найдено.')
    db.scalar(select(Seller).where(Seller.id == row.seller_id).with_for_update(of=Seller))
    db.refresh(row)
    if row.status != 'pending': raise HTTPException(409, 'Предложение не ожидает модерации.')
    owner = db.get(MerchantProduct, row.product_id)
    if owner is None or owner.status != 'approved':
        raise HTTPException(409, 'Сначала подтвердите товар.')
    if body.decision == 'approved':
        publish_listing(db, row)
        p = db.get(Product, row.product_id)
        if p and p.images: p.details.active = True
    else:
        row.status = 'rejected'; row.note = body.note
    safe_commit(db)
    return as_listing(db, row)


@admin_router.get('/catalog/classification-audit')
def classification_audit(product_id: str | None = None,
                         db: Session = Depends(get_db)):
    """Protected, read-only diagnostic for real deployed category/search data.

    Product IDs, not seller accounts, are exposed to the authenticated admin.
    This endpoint never runs inference or changes publication state.
    """
    from collections import Counter
    from sqlalchemy.orm import selectinload
    from .config import SEARCH_BACKEND
    from .ml_clip import MODEL_ID
    from .models import ImageMLEmbedding
    from .merchant_models import (ProductCategoryState,
                                  ProductCategoryAssignment, ProductSearchTag)

    statement = select(Product).options(selectinload(Product.images))
    if product_id:
        statement = statement.where(Product.id == product_id)
    products = db.scalars(statement).all()
    if not products:
        return {'total': 0, 'search_backend': SEARCH_BACKEND,
                'ml_model': MODEL_ID if SEARCH_BACKEND == 'clip' else None,
                'status_counts': {}, 'missing_image_vectors': 0,
                'missing_categories': 0, 'missing_search_tags': 0,
                'examples': []}

    status_counts = Counter()
    missing_vectors = missing_categories = missing_tags = 0
    examples = []
    for product in products:
        state = db.get(ProductCategoryState, product.id)
        assignment = db.get(ProductCategoryAssignment, product.id)
        status = state.status if state else 'state_missing'
        status_counts[status] += 1
        indexed = sum(db.get(ImageMLEmbedding, (image.id, MODEL_ID)) is not None
                      for image in product.images)
        missing_vectors += len(product.images) - indexed
        tags = [row.tag for row in db.scalars(select(ProductSearchTag).where(
            ProductSearchTag.product_id == product.id))]
        if assignment is None:
            missing_categories += 1
        if not tags:
            missing_tags += 1
        if len(examples) < 50 and (
                indexed != len(product.images) or assignment is None or not tags
                or status not in ('assigned',)):
            examples.append({
                'product_id': product.id,
                'category': product.category,
                'category_id': assignment.category_id if assignment else None,
                'status': status,
                'source': state.source if state else None,
                'photos': len(product.images),
                'indexed_photos': indexed,
                'search_tags': sorted(tags),
            })
    return {
        'total': len(products),
        'search_backend': SEARCH_BACKEND,
        'ml_model': MODEL_ID if SEARCH_BACKEND == 'clip' else None,
        'status_counts': dict(status_counts),
        'missing_image_vectors': missing_vectors,
        'missing_categories': missing_categories,
        'missing_search_tags': missing_tags,
        'examples': examples,
    }
