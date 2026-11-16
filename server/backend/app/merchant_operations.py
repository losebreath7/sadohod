"""Seller mutations. Batch changes and retry receipts share one DB transaction.

Deletion is archival: retain internal IDs for buyer history, remove live offers.
Copies own their image files; removing a copy never removes the source's files.
"""
import hashlib
import json
import logging
import shutil
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select, text, delete
from sqlalchemy.orm import Session

from . import admin, merchant as m
from .account import Buyer, current_buyer
from .database import get_db
from .models import Product, ProductDetails, ProductImage, ImageOrder, ImageMLEmbedding, Offer, Seller
from .merchant_models import MerchantProduct, MerchantListing, PavilionClaim, MerchantOperation, ProductCategoryState

router = APIRouter(prefix='/api/v1/merchant', tags=['Merchant operations'])
log = logging.getLogger(__name__)


class BatchInput(BaseModel):
    request_id: str = Field(min_length=8, max_length=80, pattern=r'^[a-zA-Z0-9_-]+$')
    product_ids: list[Annotated[str, Field(min_length=1, max_length=32)]] = Field(min_length=1, max_length=20)

    @model_validator(mode='after')
    def unique(self):
        if len(set(self.product_ids)) != len(self.product_ids):
            raise ValueError('Повторяющиеся товары')
        return self


class MoveInput(BatchInput):
    source_pavilion_id: str = Field(min_length=1, max_length=32)
    destination_pavilion_id: str = Field(min_length=1, max_length=32)


class CopyInput(BatchInput):
    source_pavilion_id: str = Field(min_length=1, max_length=32)
    destination_pavilion_ids: list[Annotated[str, Field(min_length=1, max_length=32)]] = Field(min_length=1, max_length=10)

    @model_validator(mode='after')
    def unique_destinations(self):
        if len(set(self.destination_pavilion_ids)) != len(self.destination_pavilion_ids):
            raise ValueError('Повторяющиеся павильоны')
        return self


def lock_shop(db, buyer):
    shop = m.shop_for(buyer, db)
    # Serialize concurrent batch retries and seller writes in PostgreSQL.
    db.scalar(select(Seller).where(Seller.id == shop.id).with_for_update(of=Seller))
    return shop


def receipt(db, shop, data, operation):
    digest = hashlib.sha256(json.dumps({'operation': operation, **data.model_dump()},
                                      sort_keys=True).encode()).hexdigest()
    old = db.get(MerchantOperation, (shop.id, data.request_id))
    if old and old.digest != digest:
        raise HTTPException(409, 'request_id уже использован для другого действия.')
    return digest, old.result if old else None


def finish(db, shop, data, digest, result):
    db.add(MerchantOperation(seller_id=shop.id, request_id=data.request_id, digest=digest, result=result))
    m.safe_commit(db)
    return result


def editable(db, pid, shop):
    owner = m.merchant_product(pid, shop, db)
    if owner.status == 'pending':
        raise HTTPException(409, 'Товар на модерации. Дождитесь решения.')
    return owner, db.get(Product, pid)


def claim(db, shop, pavilion):
    if not db.scalar(select(PavilionClaim).where(PavilionClaim.seller_id == shop.id,
                                                PavilionClaim.pavilion_id == pavilion)):
        raise HTTPException(403, 'Павильон не подтверждён для этого продавца.')


def drop_offer(db, row):
    offer = db.get(Offer, row.offer_id) if row.offer_id else None
    row.offer_id = None
    db.flush()
    if offer:
        db.delete(offer)
        db.flush()


def refresh_visibility(db, product, owner):
    db.flush()
    product.details.active = owner.status == 'approved' and bool(db.scalar(
        select(MerchantListing.id).where(MerchantListing.product_id == product.id,
                                        MerchantListing.offer_id.is_not(None))))


def archive(db, owner, product):
    for row in db.scalars(select(MerchantListing).where(MerchantListing.product_id == product.id)):
        drop_offer(db, row)
        row.status = 'deleted'
    product.details.active = False
    owner.status = 'deleted'
    owner.note = ''


@router.post('/products/actions/delete')
def delete_products(data: BatchInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    digest, old = receipt(db, shop, data, 'delete')
    if old is not None:
        return old
    items = [editable(db, pid, shop) for pid in data.product_ids]
    for owner, product in items:
        archive(db, owner, product)
    return finish(db, shop, data, digest, {'deleted_ids': data.product_ids})


@router.delete('/products/{pid}')
def delete_product(pid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    owner = db.get(MerchantProduct, pid)
    if not owner or owner.seller_id != shop.id:
        raise HTTPException(404, 'Товар не найден.')
    if owner.status != 'deleted':
        owner, product = editable(db, pid, shop)
        archive(db, owner, product)
        m.safe_commit(db)
    return {'id': pid, 'status': 'deleted'}


@router.delete('/products/{pid}/images/{iid}')
def delete_image(pid: str, iid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    owner, product = editable(db, pid, shop)
    img = next((i for i in product.images if i.id == iid), None)
    if not img:
        raise HTTPException(404, 'Фотография не найдена в этом товаре.')
    filename = img.filename
    db.execute(delete(ImageMLEmbedding).where(ImageMLEmbedding.image_id == iid))
    if db.bind.dialect.name == 'postgresql':
        for table in ('product_image_vectors', 'product_image_ml_vectors'):
            db.execute(text(f'DELETE FROM {table} WHERE image_id=:id'), {'id': iid})
    product.details.active = False
    owner.status = 'draft'
    owner.note = ''
    db.delete(img)
    db.flush()
    db.expire(product, ['images'])
    from .category_inference import assign_category
    assign_category(db, product)
    m.safe_commit(db)
    # A failed filesystem cleanup must not turn a successful DB mutation into 500.
    if filename.startswith('uploads/'):
        try:
            (admin.MEDIA / filename).unlink(missing_ok=True)
        except OSError:
            log.exception('Unable to remove unused image %s', iid)
    db.expire_all()
    return m.as_product(db, owner)


@router.delete('/listings/{lid}')
def delete_listing(lid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    row = m.listing_for(lid, shop, db)
    owner, product = editable(db, row.product_id, shop)
    if row.status == 'pending':
        raise HTTPException(409, 'Предложение на модерации.')
    drop_offer(db, row)
    db.delete(row)
    refresh_visibility(db, product, owner)
    m.safe_commit(db)
    return {'id': lid, 'status': 'deleted'}


@router.post('/products/actions/move')
def move_products(data: MoveInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    digest, old = receipt(db, shop, data, 'move')
    if old is not None:
        return old
    if data.source_pavilion_id == data.destination_pavilion_id:
        raise HTTPException(422, 'Выберите другой павильон.')
    claim(db, shop, data.source_pavilion_id)
    claim(db, shop, data.destination_pavilion_id)
    changes = []
    for pid in data.product_ids:
        owner, product = editable(db, pid, shop)
        rows = db.scalars(select(MerchantListing).where(MerchantListing.product_id == pid)).all()
        source = next((r for r in rows if r.pavilion_id == data.source_pavilion_id), None)
        if not source:
            raise HTTPException(409, 'Товар отсутствует в исходном павильоне.')
        if source.status == 'pending':
            raise HTTPException(409, 'Предложение на модерации.')
        if any(r.pavilion_id == data.destination_pavilion_id for r in rows):
            raise HTTPException(409, 'Товар уже размещён в выбранном павильоне.')
        changes.append((owner, product, source))
    for owner, product, row in changes:
        drop_offer(db, row)
        row.pavilion_id = data.destination_pavilion_id
        row.status = 'paused' if row.status == 'paused' else ('pending' if owner.status == 'approved' else 'draft')
        row.note = ''
        refresh_visibility(db, product, owner)
    return finish(db, shop, data, digest, {'moved_ids': data.product_ids,
                  'destination_pavilion_id': data.destination_pavilion_id})


def clone_image(db, image, pid, created_files):
    source = (admin.MEDIA / image.filename).resolve()
    if not source.is_relative_to(Path(admin.MEDIA).resolve()) or not source.is_file():
        raise HTTPException(409, 'Исходная фотография недоступна. Копирование отменено.')
    iid = m.uid('i-')
    filename = f'uploads/{iid}.jpg'
    destination = admin.MEDIA / filename
    destination.parent.mkdir(parents=True, exist_ok=True)
    created_files.append(destination)
    shutil.copyfile(source, destination)
    db.add(ProductImage(id=iid, product_id=pid, filename=filename,
                        descriptor=list(image.descriptor), ordering=ImageOrder(
                            position=image.ordering.position if image.ordering else 0)))
    db.flush()
    if db.bind.dialect.name == 'postgresql':
        db.execute(text('INSERT INTO product_image_vectors(image_id,embedding) VALUES (:id,CAST(:v AS vector))'),
                   {'id': iid, 'v': json.dumps(image.descriptor)})
    for embedding in db.scalars(select(ImageMLEmbedding).where(ImageMLEmbedding.image_id == image.id)):
        db.add(ImageMLEmbedding(image_id=iid, model_id=embedding.model_id, embedding=list(embedding.embedding)))
        if db.bind.dialect.name == 'postgresql':
            db.execute(text('INSERT INTO product_image_ml_vectors(image_id,model_id,embedding) VALUES (:id,:model,CAST(:v AS vector))'),
                       {'id': iid, 'model': embedding.model_id, 'v': json.dumps(embedding.embedding)})


@router.post('/products/actions/copy', status_code=201)
def copy_products(data: CopyInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    digest, old = receipt(db, shop, data, 'copy')
    if old is not None:
        return old
    claim(db, shop, data.source_pavilion_id)
    for pavilion in data.destination_pavilion_ids:
        claim(db, shop, pavilion)
    sources = []
    for pid in data.product_ids:
        _, product = editable(db, pid, shop)
        row = db.scalar(select(MerchantListing).where(MerchantListing.product_id == pid,
                        MerchantListing.pavilion_id == data.source_pavilion_id))
        if not row or row.status == 'pending':
            raise HTTPException(409, 'Исходное предложение недоступно или на модерации.')
        sources.append((product, row))
    created_files, items = [], []
    try:
        for original, listing in sources:
            pid = m.uid('u-')
            product = Product(id=pid, title=original.title, category=original.category,
                              description=original.description, colors=list(original.colors), is_demo=False,
                              details=ProductDetails(active=False, sizes=list(original.details.sizes)))
            db.add(product)
            db.flush()
            db.add(MerchantProduct(product_id=pid, seller_id=shop.id, status='draft'))
            category_state = db.get(ProductCategoryState, original.id)
            if category_state:
                db.add(ProductCategoryState(product_id=pid, source=category_state.source,
                       status=category_state.status, assigned=category_state.assigned,
                       suggestion=category_state.suggestion, score=category_state.score))
            for image in original.images:
                clone_image(db, image, pid, created_files)
            for pavilion in data.destination_pavilion_ids:
                db.add(MerchantListing(id=m.uid('l-'), product_id=pid, seller_id=shop.id,
                       pavilion_id=pavilion, price=listing.price, wholesale=listing.wholesale,
                       retail=listing.retail, status='draft'))
            items.append({'source_id': original.id, 'id': pid})
        return finish(db, shop, data, digest, {'copies': items})
    except Exception:
        db.rollback()
        for path in created_files:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                log.exception('Unable to remove incomplete copy')
        raise


@router.post('/products/{pid}/classify')
def classify_product(pid: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    owner, product = editable(db, pid, shop)
    if owner.status == 'approved':
        raise HTTPException(409, 'Сначала переведите товар в черновик для повторной модерации.')
    from .category_inference import assign_category
    assign_category(db, product)
    m.safe_commit(db)
    return m.as_product(db, owner)


class SaveInput(m.DraftProductInput):
    listings: list[m.ListingInput] = Field(min_length=1, max_length=50)
    submit: bool = True


@router.put('/products/{pid}/save')
def save_product(pid: str, data: SaveInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    shop = lock_shop(db, buyer)
    if not data.request_id:
        raise HTTPException(422, 'Нужен ключ сохранения request_id.')
    digest, old = receipt(db, shop, data, 'save:' + pid)
    if old is not None:
        return m.as_product(db, m.merchant_product(pid, shop, db))
    owner, product = editable(db, pid, shop)
    ids = [r.pavilion_id for r in data.listings]
    if len(set(ids)) != len(ids):
        raise HTTPException(422, 'Павильоны не должны повторяться.')
    for pavilion in ids:
        claim(db, shop, pavilion)
    if data.submit and not product.images:
        raise HTTPException(409, 'Добавьте хотя бы одну фотографию.')
    existing = db.scalars(select(MerchantListing).where(MerchantListing.product_id == pid)).all()
    if any(r.status == 'pending' for r in existing):
        raise HTTPException(409, 'Предложение уже на модерации.')
    product.title = data.title.strip() or 'Без названия'
    product.category = data.category.strip() or 'Без категории'
    product.description = data.description.strip()
    product.colors = data.colors
    product.details.sizes = data.sizes
    product.details.active = False
    from .category_inference import assign_category
    assign_category(db, product)
    for row in existing:
        if row.pavilion_id not in ids:
            drop_offer(db, row)
            db.delete(row)
    for value in data.listings:
        row = next((r for r in existing if r.pavilion_id == value.pavilion_id), None)
        if row is None:
            row = MerchantListing(id=m.uid('l-'), product_id=pid, seller_id=shop.id, pavilion_id=value.pavilion_id)
            db.add(row)
        row.price = value.price
        row.wholesale = 'wholesale' in value.sale_modes
        row.retail = 'retail' in value.sale_modes
        row.status = 'pending' if data.submit else 'draft'
        row.note = ''
    owner.status = 'pending' if data.submit else 'draft'
    owner.note = ''
    finish(db, shop, data, digest, {'id': pid})
    return m.as_product(db, owner)
