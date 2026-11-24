"""Authenticated Sadohodets profile lifecycle; publication is explicit."""
import re
import time
import uuid
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import case, delete, func, select
from sqlalchemy.orm import Session

from .account import Buyer, current_buyer
from .database import get_db
from .sadohodets_models import SadohodetsProfile, SadohodetsFolder, SadohodetsFolderItem, SadohodetsReview

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
    folders = select(SadohodetsFolder.id).where(SadohodetsFolder.owner_id == buyer_id)
    db.execute(delete(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id.in_(folders)))
    db.execute(delete(SadohodetsFolder).where(SadohodetsFolder.owner_id == buyer_id))
    db.execute(delete(SadohodetsReview).where(SadohodetsReview.profile_id == buyer_id))
    if delete_written_reviews:
        db.execute(delete(SadohodetsReview).where(SadohodetsReview.reviewer_id == buyer_id))
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


class CollectedInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    collected: bool


def folder_data(row):
    return {'id': row.id, 'name': row.name, 'note': row.note, 'created_at': row.created_at}


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
def create_folder(body: FolderInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    own_profile(db, buyer.id, lock=True)
    count = db.scalar(select(func.count()).select_from(SadohodetsFolder).where(SadohodetsFolder.owner_id == buyer.id))
    if count >= 500:
        raise HTTPException(409, 'Достигнут лимит папок.')
    row = SadohodetsFolder(id=uuid.uuid4().hex, owner_id=buyer.id, name=body.name,
                           note=body.note, created_at=time.time())
    db.add(row)
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
        {'product_id': i.product_id, 'collected': i.collected, 'added_at': i.added_at,
         'product': products.get(i.product_id), 'available': i.product_id in products} for i in items]}


@router.put('/me/folders/{folder_id}')
def update_folder(folder_id: str, body: FolderInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    row.name, row.note = body.name, body.note
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
    if item is None:
        if db.scalar(select(Product.id).where(Product.id == product_id, visible_products())) is None:
            raise HTTPException(404, 'Товар не найден.')
        count = db.scalar(select(func.count()).select_from(SadohodetsFolderItem).where(SadohodetsFolderItem.folder_id == row.id))
        if count >= 500:
            raise HTTPException(409, 'Достигнут лимит товаров в папке.')
        item = SadohodetsFolderItem(folder_id=row.id, product_id=product_id, collected=False, added_at=time.time())
        db.add(item)
    touch_profile(db, buyer.id)
    db.commit()
    return {'product_id': item.product_id, 'collected': item.collected}


@router.patch('/me/folders/{folder_id}/items/{product_id}')
def mark_folder_item(folder_id: str, product_id: str, body: CollectedInput,
                     buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row = owned_folder(db, buyer.id, folder_id)
    item = db.get(SadohodetsFolderItem, (row.id, product_id))
    if item is None:
        raise HTTPException(404, 'Товар не найден в папке.')
    item.collected = body.collected
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
