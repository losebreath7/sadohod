"""Authenticated Sadohodets profile lifecycle; publication is explicit."""
import re
import time
import uuid
from typing import Literal
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import and_, case, delete, func, or_, select
from sqlalchemy.orm import Session

from .account import Buyer, Favorite, current_buyer
from .admin_auth import require_admin
from .database import get_db
from .sadohodets_models import SadohodetsProfile, SadohodetsFolder, SadohodetsFolderItem, SadohodetsReview, SadohodetsMedia

router = APIRouter(prefix='/api/v1/sadohodets', tags=['sadohodets'])
CONTACT_KEYS = {'phone', 'phone2', 'telegram', 'vk', 'whatsapp', 'avito', 'website'}


class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default='', max_length=2000)
    contacts: dict[str, str] = Field(default_factory=dict, max_length=7)

    @field_validator('contacts')
    @classmethod
    def validate_contacts(cls, values):
        clean = {}
        for key, raw in values.items():
            if key not in CONTACT_KEYS:
                raise ValueError('Неизвестный тип контакта')
            value = raw.strip()
            if not value:
                continue
            if len(value) > 250 or any(ord(c) < 32 or ord(c) == 127 for c in value):
                raise ValueError('Некорректный контакт')
            if key in {'phone', 'phone2', 'whatsapp'} and not value.startswith('https://'):
                if not re.fullmatch(r'\+?[0-9 ()-]{7,25}', value) or not 7 <= len(re.sub(r'\D', '', value)) <= 15:
                    raise ValueError('Некорректный номер телефона')
            elif key == 'vk' and re.fullmatch(r'@?[A-Za-z0-9_.-]{2,64}', value):
                value = 'https://vk.com/' + value.lstrip('@')
            elif key == 'telegram' and re.fullmatch(r'@?[A-Za-z0-9_]{5,32}', value):
                value = 'https://t.me/' + value.lstrip('@')
            else:
                try:
                    url = urlsplit(value)
                    host = (url.hostname or '').lower()
                    if url.scheme != 'https' or not host or '.' not in host or url.username or url.password or any(c.isspace() for c in value):
                        raise ValueError()
                    allowed = {'telegram': ('t.me', 'telegram.me'), 'vk': ('vk.com', 'vk.ru'), 'whatsapp': ('wa.me', 'whatsapp.com'), 'avito': ('avito.ru',)}
                    if key in {'phone', 'phone2'}:
                        raise ValueError()
                    if key in allowed and not any(host == h or host.endswith('.' + h) for h in allowed[key]):
                        raise ValueError()
                except ValueError:
                    raise ValueError('Некорректная ссылка контакта')
            clean[key] = value
        return clean


class PublicationInput(BaseModel):
    published: bool


def own_profile(db, buyer_id, *, lock=False):
    if lock:
        db.scalar(select(Buyer.id).where(Buyer.id == buyer_id).with_for_update())
    row = db.get(SadohodetsProfile, buyer_id)
    if row is None:
        raise HTTPException(404, 'Анкета садоходца ещё не создана.')
    return row


def serialize(row):
    return {'id': row.buyer_id, 'name': row.name, 'description': row.description,
            'contacts': row.contacts, 'avatar': row.avatar, 'cover': row.cover,
            'published': row.published, 'last_active_at': row.last_active_at}


@router.get('/me')
def get_me(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = own_profile(db, buyer.id, lock=True)
    now = time.time()
    if now - row.last_active_at >= 300:
        row.last_active_at = now
        db.commit()
    return serialize(row)


@router.put('/me')
def save_me(body: ProfileInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.scalar(select(Buyer.id).where(Buyer.id == buyer.id).with_for_update())
    row = db.get(SadohodetsProfile, buyer.id)
    now = time.time()
    if row is None:
        row = SadohodetsProfile(buyer_id=buyer.id, created_at=now, published=False)
        db.add(row)
    row.name = body.name
    row.description = body.description
    row.contacts = body.contacts
    row.last_active_at = now
    if not row.contacts:
        row.published = False
    db.commit()
    return serialize(row)


@router.put('/me/publication')
def set_publication(body: PublicationInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = own_profile(db, buyer.id, lock=True)
    if body.published and not row.contacts:
        raise HTTPException(422, 'Добавьте хотя бы один контакт.')
    row.published = body.published
    row.last_active_at = time.time()
    db.commit()
    return serialize(row)


def delete_profile_data(db, buyer_id, *, delete_written_reviews=False):
    db.execute(delete(Favorite).where(Favorite.kind == 'courier', Favorite.item == buyer_id))
    folders = select(SadohodetsFolder.id).where(SadohodetsFolder.owner_id == buyer_id)
    db.execute(delete(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id.in_(folders)))
    db.execute(delete(SadohodetsFolder).where(SadohodetsFolder.owner_id == buyer_id))
    db.execute(delete(SadohodetsReview).where(SadohodetsReview.profile_id == buyer_id))
    if delete_written_reviews:
        db.execute(delete(SadohodetsReview).where(SadohodetsReview.reviewer_id == buyer_id))
    from .seller_notifications import SellerNotification
    db.execute(delete(SellerNotification).where(SellerNotification.buyer_id == buyer_id, SellerNotification.event_type == 'courier_review'))
    db.execute(delete(SadohodetsMedia).where(SadohodetsMedia.profile_id == buyer_id))
    db.execute(delete(SadohodetsProfile).where(SadohodetsProfile.buyer_id == buyer_id))


@router.delete('/me')
def delete_me(buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    own_profile(db, buyer.id, lock=True)
    delete_profile_data(db, buyer.id)
    db.commit()
    return {'ok': True}


# Private client folders. Mutations share the same account lock as profile deletion.
class FolderInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    note: str = Field(default='', max_length=4000)
    client_link: str | None = Field(default=None, max_length=2048)

    @field_validator('client_link')
    @classmethod
    def validate_client_link(cls, value):
        if not value:
            return value
        if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in value) or '\\' in value:
            raise ValueError('Введите корректную HTTPS-ссылку на клиента')
        try:
            url = urlsplit(value)
            if url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None or '.' not in url.hostname:
                raise ValueError('Введите корректную HTTPS-ссылку на клиента')
            _ = url.port
        except ValueError:
            raise ValueError('Введите корректную HTTPS-ссылку на клиента')
        return value


class CreateFolderInput(FolderInput):
    product_id: str | None = Field(default=None, min_length=1, max_length=32)


class ItemUpdateInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    collected: bool | None = None
    note: str | None = Field(default=None, max_length=250)


def folder_data(row):
    return {'id': row.id, 'name': row.name, 'note': row.note, 'client_link': row.client_link, 'created_at': row.created_at}


def owned_folder(db, buyer_id, folder_id):
    own_profile(db, buyer_id, lock=True)
    row = db.scalar(select(SadohodetsFolder).where(
        SadohodetsFolder.id == folder_id, SadohodetsFolder.owner_id == buyer_id))
    if row is None:
        raise HTTPException(404, 'Папка не найдена.')
    return row


def touch_profile(db, buyer_id):
    row = db.get(SadohodetsProfile, buyer_id)
    row.last_active_at = time.time()


@router.get('/me/folders')
def list_folders(limit: int = Query(100, ge=1, le=200), offset: int = Query(0, ge=0),
                 buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    own_profile(db, buyer.id)
    count = func.count(SadohodetsFolderItem.product_id)
    done = func.coalesce(func.sum(case((SadohodetsFolderItem.collected.is_(True), 1), else_=0)), 0)
    rows = db.execute(select(SadohodetsFolder, count, done)
        .outerjoin(SadohodetsFolderItem, SadohodetsFolderItem.folder_id == SadohodetsFolder.id)
        .where(SadohodetsFolder.owner_id == buyer.id)
        .group_by(SadohodetsFolder.id)
        .order_by(SadohodetsFolder.created_at.desc(), SadohodetsFolder.id)
        .limit(limit).offset(offset)).all()
    return {'items': [{**folder_data(row), 'count': n, 'collected_count': d} for row, n, d in rows]}


@router.post('/me/folders', status_code=201)
def create_folder(body: CreateFolderInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    own_profile(db, buyer.id, lock=True)
    count = db.scalar(select(func.count()).select_from(SadohodetsFolder).where(SadohodetsFolder.owner_id == buyer.id))
    if count >= 500:
        raise HTTPException(409, 'Достигнут лимит папок.')
    row = SadohodetsFolder(id=uuid.uuid4().hex, owner_id=buyer.id, name=body.name,
                           note=body.note, client_link=body.client_link or '', created_at=time.time())
    if body.product_id is not None:
        from .api import visible_products
        from .models import Product
        if db.scalar(select(Product.id).where(Product.id == body.product_id, visible_products())) is None:
            raise HTTPException(404, 'Товар не найден.')
    db.add(row)
    if body.product_id is not None:
        db.flush()
        db.add(SadohodetsFolderItem(folder_id=row.id, product_id=body.product_id,
                                   collected=False, added_at=time.time()))
    touch_profile(db, buyer.id)
    db.commit()
    return folder_data(row)


@router.get('/me/folders/{folder_id}')
def get_folder(folder_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    from .api import product_query, serialize_product
    from .models import Product
    row = owned_folder(db, buyer.id, folder_id)
    items = db.scalars(select(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id == row.id)
                       .order_by(SadohodetsFolderItem.added_at, SadohodetsFolderItem.product_id)).all()
    products = {}
    if items:
        products = {p.id: serialize_product(p) for p in db.scalars(
            product_query().where(Product.id.in_([i.product_id for i in items]))).unique()}
    return {**folder_data(row), 'items': [
        {'product_id': i.product_id, 'collected': i.collected, 'note': i.note, 'added_at': i.added_at,
         'product': products.get(i.product_id), 'available': i.product_id in products} for i in items]}


@router.put('/me/folders/{folder_id}')
def update_folder(folder_id: str, body: FolderInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    row.name, row.note = body.name, body.note
    if body.client_link is not None:
        row.client_link = body.client_link
    touch_profile(db, buyer.id)
    db.commit()
    return folder_data(row)


@router.delete('/me/folders/{folder_id}')
def remove_folder(folder_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    db.execute(delete(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id == row.id))
    db.delete(row)
    touch_profile(db, buyer.id)
    db.commit()
    return {'ok': True}


@router.put('/me/folders/{folder_id}/items/{product_id}')
def add_folder_item(folder_id: str, product_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    from .api import visible_products
    from .models import Product
    row = owned_folder(db, buyer.id, folder_id)
    item = db.get(SadohodetsFolderItem, (row.id, product_id))
    added = item is None
    if added:
        if db.scalar(select(Product.id).where(Product.id == product_id, visible_products())) is None:
            raise HTTPException(404, 'Товар не найден.')
        count = db.scalar(select(func.count()).select_from(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id == row.id))
        if count >= 500:
            raise HTTPException(409, 'Достигнут лимит товаров в папке.')
        item = SadohodetsFolderItem(folder_id=row.id, product_id=product_id, collected=False, added_at=time.time())
        db.add(item)
    touch_profile(db, buyer.id)
    db.commit()
    return {'product_id': item.product_id, 'collected': item.collected, 'added': added}


@router.patch('/me/folders/{folder_id}/items/{product_id}')
def mark_folder_item(folder_id: str, product_id: str, body: ItemUpdateInput,
                     buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    item = db.get(SadohodetsFolderItem, (row.id, product_id))
    if item is None:
        raise HTTPException(404, 'Товар не найден в папке.')
    if body.collected is not None:
        item.collected = body.collected
    if body.note is not None:
        item.note = body.note.strip()
    touch_profile(db, buyer.id)
    db.commit()
    return {'product_id': product_id, 'collected': item.collected}


@router.delete('/me/folders/{folder_id}/items/{product_id}')
def remove_folder_item(folder_id: str, product_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    db.execute(delete(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id == row.id,
                                                SadohodetsFolderItem.product_id == product_id))
    touch_profile(db, buyer.id)
    db.commit()
    return {'ok': True}


# Public directory: account restrictions are applied before pagination and ranking.
def not_blocked(buyer_column):
    from .moderation_enforcement_models import AccountRestriction
    return ~select(AccountRestriction.buyer_id).where(
        AccountRestriction.buyer_id == buyer_column,
        AccountRestriction.active.is_(True),
        or_(AccountRestriction.until.is_(None), AccountRestriction.until > time.time())
    ).exists()


def public_profiles():
    return select(SadohodetsProfile).where(
        SadohodetsProfile.published.is_(True),
        not_blocked(SadohodetsProfile.buyer_id))


def public_profile(db, profile_id):
    row = db.scalar(public_profiles().where(SadohodetsProfile.buyer_id == profile_id))
    if row is None:
        raise HTTPException(404, 'Садоходец не найден.')
    return row


def approved_reviews():
    return and_(SadohodetsReview.moderation_status == 'approved',
                not_blocked(SadohodetsReview.reviewer_id))


def review_stats(db, profile_id):
    average, count = db.execute(select(func.avg(SadohodetsReview.rating), func.count())
        .where(SadohodetsReview.profile_id == profile_id, approved_reviews())).one()
    return {'rating': round(float(average), 2) if average is not None else None,
            'review_count': count}


@router.get('')
def directory(sort: Literal['rating', 'activity'] = 'rating',
              min_rating: int = Query(0, ge=0, le=5),
              active_days: int | None = Query(None, ge=1, le=365),
              limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0),
              db: Session = Depends(get_db)):
    stats = select(SadohodetsReview.profile_id.label('pid'),
                   func.avg(SadohodetsReview.rating).label('rating'),
                   func.count().label('review_count')).where(approved_reviews()).group_by(
                       SadohodetsReview.profile_id).subquery()
    statement = public_profiles().add_columns(stats.c.rating, stats.c.review_count).outerjoin(
        stats, stats.c.pid == SadohodetsProfile.buyer_id)
    if min_rating:
        statement = statement.where(stats.c.rating >= min_rating)
    if active_days is not None:
        now = time.time()
        # 'Сегодня' starts at midnight at the market in Moscow (UTC+3).
        since = ((now + 10800) // 86400) * 86400 - 10800 if active_days == 1 else now - active_days * 86400
        statement = statement.where(SadohodetsProfile.last_active_at >= since)
    rating_order = func.coalesce(stats.c.rating, 0).desc()
    activity_order = SadohodetsProfile.last_active_at.desc()
    orders = (rating_order, activity_order) if sort == 'rating' else (activity_order, rating_order)
    rows = db.execute(statement.order_by(*orders, SadohodetsProfile.buyer_id).limit(limit).offset(offset)).all()
    return {'items': [{**serialize(row), 'rating': round(float(rating), 2) if rating is not None else None,
                       'review_count': count or 0} for row, rating, count in rows]}


class ReviewInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    rating: int = Field(ge=1, le=5, strict=True)
    text: str = Field(default='', max_length=2000)


def review_data(row, name):
    return {'rating': row.rating, 'text': row.body, 'name': (name or '').strip() or 'Пользователь',
            'created_at': row.created_at, 'moderation_status': row.moderation_status}


class ReviewModerationInput(BaseModel):
    status: Literal['approved', 'hidden', 'pending']

@router.get('/admin/reviews', dependencies=[Depends(require_admin)])
def moderation_queue(status: Literal['pending', 'approved', 'hidden'] = 'pending',
                     limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0),
                     db: Session = Depends(get_db)):
    rows = db.scalars(select(SadohodetsReview).where(SadohodetsReview.moderation_status == status)
        .order_by(SadohodetsReview.created_at.desc(), SadohodetsReview.profile_id, SadohodetsReview.reviewer_id)
        .limit(limit).offset(offset)).all()
    return {'items': [{'profile_id': row.profile_id, 'reviewer_id': row.reviewer_id,
                       **review_data(row, '')} for row in rows]}


@router.put('/admin/reviews/{profile_id}/{reviewer_id}', dependencies=[Depends(require_admin)])
def moderate_review(profile_id: str, reviewer_id: str, body: ReviewModerationInput,
                    db: Session = Depends(get_db)):
    row = db.get(SadohodetsReview, (profile_id, reviewer_id))
    if row is None:
        raise HTTPException(404, 'Отзыв не найден.')
    previous = row.moderation_status
    row.moderation_status = body.status
    if previous != body.status and body.status == 'approved':
        from .seller_notifications import SellerNotification
        db.add(SellerNotification(id=uuid.uuid4().hex, buyer_id=profile_id,
            event_type='courier_review', status='approved', target_id=profile_id,
            title='Новый отзыв', message='В вашей карточке опубликован новый отзыв.',
            note='', created_at=time.time()))
    db.commit()
    return {'ok': True}


@router.get('/{profile_id}/reviews')
def list_reviews(profile_id: str, limit: int = Query(50, ge=1, le=100),
                 offset: int = Query(0, ge=0), db: Session = Depends(get_db)):
    public_profile(db, profile_id)
    rows = db.execute(select(SadohodetsReview, Buyer.name).join(
        Buyer, Buyer.id == SadohodetsReview.reviewer_id).where(
        SadohodetsReview.profile_id == profile_id, approved_reviews()).order_by(
        SadohodetsReview.created_at.desc(), SadohodetsReview.reviewer_id).limit(limit).offset(offset)).all()
    return {**review_stats(db, profile_id), 'items': [review_data(row, name) for row, name in rows],
            'verified_purchases': False}


@router.get('/{profile_id}/my-review')
def my_review(profile_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    public_profile(db, profile_id)
    row = db.get(SadohodetsReview, (profile_id, buyer.id))
    return {'item': review_data(row, buyer.name) if row else None}


@router.put('/{profile_id}/my-review')
def save_review(profile_id: str, body: ReviewInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    if profile_id == buyer.id:
        raise HTTPException(403, 'Нельзя оставить отзыв о себе.')
    db.scalar(select(Buyer.id).where(Buyer.id == buyer.id).with_for_update())
    public_profile(db, profile_id)
    row = db.get(SadohodetsReview, (profile_id, buyer.id))
    if row is None:
        row = SadohodetsReview(profile_id=profile_id, reviewer_id=buyer.id, created_at=time.time())
        db.add(row)
    if row.moderation_status == 'hidden':
        raise HTTPException(403, 'Отзыв скрыт модератором.')
    row.rating, row.body, row.moderation_status = body.rating, body.text, 'pending'
    db.commit()
    return {'item': review_data(row, buyer.name)}


@router.delete('/{profile_id}/my-review')
def remove_review(profile_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    db.scalar(select(Buyer.id).where(Buyer.id == buyer.id).with_for_update())
    db.execute(delete(SadohodetsReview).where(SadohodetsReview.profile_id == profile_id,
                                             SadohodetsReview.reviewer_id == buyer.id))
    db.commit()
    return {'ok': True}





@router.get('/{profile_id}')
def directory_profile(profile_id: str, db: Session = Depends(get_db)):
    row = public_profile(db, profile_id)
    return {**serialize(row), **review_stats(db, profile_id)}


# Media is stored separately from the directory response to avoid embedding
# large base64 images in every paginated list.
class ProfileMediaInput(BaseModel):
    data: str = Field(min_length=10, max_length=2_000_000)


@router.put('/me/media/{kind}')
def upload_profile_media(kind: Literal['avatar', 'cover'], body: ProfileMediaInput,
                         buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    import base64
    import binascii
    import io
    from PIL import Image, ImageOps, UnidentifiedImageError
    row = own_profile(db, buyer.id, lock=True)
    try:
        raw = base64.b64decode(body.data, validate=True)
        if len(raw) > 1_500_000:
            raise HTTPException(413, 'Изображение должно быть меньше 1,5 МБ.')
        with Image.open(io.BytesIO(raw)) as image:
            if image.format not in {'JPEG', 'PNG', 'WEBP'} or image.width * image.height > 25_000_000:
                raise ValueError('Unsupported image')
            image = ImageOps.exif_transpose(image)
            image.thumbnail((1600, 900) if kind == 'cover' else (600, 600))
            buf = io.BytesIO()
            image.convert('RGB').save(buf, format='JPEG', quality=78, optimize=True)
        raw = buf.getvalue()
    except (ValueError, binascii.Error, OSError, UnidentifiedImageError, Image.DecompressionBombError):
        raise HTTPException(422, 'Не удалось прочитать изображение.') from None
    item = db.get(SadohodetsMedia, (buyer.id, kind))
    if item is None:
        item = SadohodetsMedia(profile_id=buyer.id, kind=kind, raw=raw)
        db.add(item)
    else:
        item.raw = raw
    setattr(row, kind, f'/api/v1/sadohodets/{buyer.id}/media/{kind}')
    touch_profile(db, buyer.id)
    db.commit()
    return serialize(row)


@router.delete('/me/media/{kind}')
def delete_profile_media(kind: Literal['avatar', 'cover'], buyer: Buyer = Depends(current_buyer),
                         db: Session = Depends(get_db)):
    row = own_profile(db, buyer.id, lock=True)
    db.execute(delete(SadohodetsMedia).where(SadohodetsMedia.profile_id == buyer.id, SadohodetsMedia.kind == kind))
    setattr(row, kind, None)
    db.commit()
    return serialize(row)


@router.get('/me/media/{kind}')
def own_media(kind: Literal['avatar', 'cover'], buyer: Buyer = Depends(current_buyer),
              db: Session = Depends(get_db)):
    own_profile(db, buyer.id)
    return media_response(db, buyer.id, kind)


def media_response(db, profile_id, kind):
    from fastapi.responses import Response
    item = db.get(SadohodetsMedia, (profile_id, kind))
    if item is None:
        raise HTTPException(404, 'Изображение не найдено.')
    return Response(item.raw, media_type='image/jpeg', headers={'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'})


@router.get('/{profile_id}/media/{kind}')
def public_media(profile_id: str, kind: Literal['avatar', 'cover'], db: Session = Depends(get_db)):
    public_profile(db, profile_id)
    return media_response(db, profile_id, kind)
