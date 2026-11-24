"""Authenticated Sadohodets profile lifecycle; publication is explicit."""
import re
import time
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, select
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
