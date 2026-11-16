"""Small local catalog editor. Writes are authenticated; uploads are indexed before commit."""
import logging
import math
import uuid
from io import BytesIO
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field, StringConstraints
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select, text, delete
from sqlalchemy.orm import Session

from .admin_auth import require_admin
from .api import product_query, serialize_product, serialize_seller
from .config import MEDIA, MAX_UPLOAD_BYTES, SEARCH_BACKEND
from .database import get_db
from .build_info import BUILD_INFO
from .image_features import descriptor_from_bytes
from .ml_clip import embed_image, MODEL_ID, DIM
from .models import Seller, Pavilion, SellerDetails, Product, ProductDetails, Offer, OfferSaleModes, ProductImage, ImageMLEmbedding, ImageOrder

router = APIRouter(prefix='/api/v1/admin', dependencies=[Depends(require_admin)])
Short = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]


class SellerInput(BaseModel):
    name: Name
    contact: str = Field(default='', max_length=500)
    pavilion: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=32)]
    zone: Title


class ProductInput(BaseModel):
    title: Title
    category: Short
    description: str = Field(default='', max_length=5000)
    colors: list[Short] = Field(default_factory=list, max_length=30)
    sizes: list[Short] = Field(default_factory=list, max_length=30)
    seller_id: str = Field(min_length=1, max_length=32)
    price: int = Field(ge=0, le=100000000, strict=True)
    # None keeps compatibility with older edit clients. A new offer cannot be
    # published until an explicit retail/wholesale selection is supplied.
    sale_modes: list[Literal['wholesale', 'retail']] | None = Field(default=None, min_length=1, max_length=2)


class VisibilityInput(BaseModel):
    active: bool


def uid(prefix):
    return prefix + uuid.uuid4().hex[:24]


def get_product(session, pid):
    product = session.scalar(product_query(include_hidden=True).where(Product.id == pid))
    if product is None:
        raise HTTPException(404, 'Товар не найден')
    return product


def get_seller(session, sid):
    seller = session.get(Seller, sid)
    if seller is None:
        raise HTTPException(404, 'Продавец не найден')
    return seller


@router.get('/status')
def status():
    return {**BUILD_INFO, 'search_backend': SEARCH_BACKEND}


@router.get('/sellers')
def sellers(session: Session = Depends(get_db)):
    return {'items': [serialize_seller(s) for s in session.scalars(select(Seller).order_by(Seller.name))]}


@router.post('/sellers', status_code=201)
def create_seller(data: SellerInput, session: Session = Depends(get_db)):
    sid=uid('s-')
    pavilion=Pavilion(id=sid, code=data.pavilion, zone=data.zone)
    seller=Seller(id=sid, name=data.name, pavilion=pavilion, details=SellerDetails(contact=data.contact))
    session.add(seller)
    session.commit()
    return serialize_seller(seller)


@router.put('/sellers/{sid}')
def edit_seller(sid: str, data: SellerInput, session: Session = Depends(get_db)):
    seller=get_seller(session,sid)
    seller.name=data.name
    seller.pavilion.code=data.pavilion
    seller.pavilion.zone=data.zone
    if seller.details is None:
        seller.details=SellerDetails(contact=data.contact, is_demo=True)
    else:
        seller.details.contact=data.contact
    session.commit()
    return serialize_seller(seller)


@router.get('/products')
def products(session: Session = Depends(get_db)):
    return {'items':[serialize_product(p) for p in session.scalars(product_query(include_hidden=True).order_by(Product.id))]}


@router.post('/products', status_code=201)
def create_product(data: ProductInput, session: Session = Depends(get_db)):
    seller=get_seller(session,data.seller_id)
    pid=uid('u-')
    product=Product(id=pid, title=data.title, category=data.category, description=data.description,
                    colors=data.colors, is_demo=False, details=ProductDetails(active=False,sizes=data.sizes))
    offer=Offer(id=uid('o-'),seller_id=seller.id,pavilion_id=seller.pavilion_id,price=data.price)
    if data.sale_modes is not None:
        offer.modes=OfferSaleModes(wholesale='wholesale' in data.sale_modes,retail='retail' in data.sale_modes)
    product.offers=[offer]
    session.add(product)
    session.commit()
    return serialize_product(product)


@router.put('/products/{pid}')
def edit_product(pid: str, data: ProductInput, session: Session = Depends(get_db)):
    product=get_product(session,pid)
    seller=get_seller(session,data.seller_id)
    # Existing multi-seller offers must not be silently replaced by this single-offer editor.
    if len(product.offers)>1:
        raise HTTPException(409,'У товара несколько предложений. Их редактирование появится отдельно.')
    product.title=data.title; product.category=data.category
    product.description=data.description; product.colors=data.colors
    if product.details is None:
        product.details=ProductDetails(active=True,sizes=data.sizes)
    else:
        product.details.sizes=data.sizes
    if product.offers:
        offer=product.offers[0]
        offer.seller_id=seller.id; offer.pavilion_id=seller.pavilion_id; offer.price=data.price
        if data.sale_modes is not None:
            if offer.modes is None: offer.modes=OfferSaleModes()
            offer.modes.wholesale='wholesale' in data.sale_modes
            offer.modes.retail='retail' in data.sale_modes
    else:
        offer=Offer(id=uid('o-'),seller_id=seller.id,pavilion_id=seller.pavilion_id,price=data.price)
        if data.sale_modes is not None:
            offer.modes=OfferSaleModes(wholesale='wholesale' in data.sale_modes,retail='retail' in data.sale_modes)
        product.offers=[offer]
    session.commit()
    session.expire_all()
    return serialize_product(get_product(session,pid))


@router.put('/products/{pid}/visibility')
def visibility(pid: str, data: VisibilityInput, session: Session = Depends(get_db)):
    product=get_product(session,pid)
    if data.active and (not product.images or not product.offers):
        raise HTTPException(409,'Перед публикацией добавьте фотографию и предложение продавца.')
    if data.active and not product.is_demo and any(
        o.modes is None or not (o.modes.wholesale or o.modes.retail) for o in product.offers
    ):
        raise HTTPException(409,'Укажите доступный способ продажи: опт и/или розница.')
    if data.active and SEARCH_BACKEND=='clip':
        for img in product.images:
            if session.get(ImageMLEmbedding,(img.id,MODEL_ID)) is None:
                raise HTTPException(409,'Фотография ещё не подготовлена для OpenCLIP. Перезапустите ML-режим.')
    if product.details is None:
        product.details=ProductDetails(active=data.active,sizes=[])
    else:
        product.details.active=data.active
    session.commit()
    return serialize_product(product)


def normalize_image(raw):
    try:
        with Image.open(BytesIO(raw)) as source:
            if source.format not in ('JPEG','PNG','WEBP'):
                raise ValueError('format')
            if source.width*source.height>20_000_000 or min(source.size)<24:
                raise ValueError('size')
            im=ImageOps.exif_transpose(source).convert('RGB')
            im.thumbnail((1800,1800), Image.Resampling.LANCZOS)
            out=BytesIO(); im.save(out,'JPEG',quality=92)
            return out.getvalue()
    except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError) as e:
        raise HTTPException(422,'Нужна корректная фотография JPEG, PNG или WebP: от 24 px, не более 20 мегапикселей.') from e


@router.post('/products/{pid}/images', status_code=201)
def upload_images(pid: str, files: list[UploadFile] = File(...), session: Session = Depends(get_db)):
    product=get_product(session,pid)
    if not 1<=len(files)<=6 or len(product.images)+len(files)>12:
        raise HTTPException(422,'За раз можно добавить до 6 фотографий; всего — до 12 на товар.')
    prepared=[]; written=[]
    try:
        for f in files:
            raw=f.file.read(MAX_UPLOAD_BYTES+1)
            if len(raw)>MAX_UPLOAD_BYTES:
                raise HTTPException(413,'Каждая фотография должна быть не больше 8 МБ.')
            clean=normalize_image(raw)
            descriptor=descriptor_from_bytes(clean)
            vector=embed_image(clean) if SEARCH_BACKEND=='clip' else None
            if vector is not None and (len(vector)!=DIM or not all(math.isfinite(v) for v in vector)):
                raise RuntimeError('Некорректный ML-вектор')
            prepared.append((clean,descriptor,vector))
        folder=MEDIA/'uploads'; folder.mkdir(parents=True,exist_ok=True)
        position=max((i.ordering.position if i.ordering else -1 for i in product.images),default=-1)+1
        for offset,(clean,descriptor,vector) in enumerate(prepared):
            iid=uid('i-'); filename=f'uploads/{uuid.uuid4().hex}.jpg'
            path=MEDIA/filename
            written.append(path)
            path.write_bytes(clean)
            session.add(ProductImage(id=iid,product_id=pid,filename=filename,descriptor=descriptor,ordering=ImageOrder(position=position+offset)))
            session.flush()
            if session.bind.dialect.name=='postgresql':
                literal='['+','.join(str(v) for v in descriptor)+']'
                session.execute(text('INSERT INTO product_image_vectors(image_id,embedding) VALUES (:id,CAST(:v AS vector))'),{'id':iid,'v':literal})
            if vector is not None:
                session.add(ImageMLEmbedding(image_id=iid,model_id=MODEL_ID,embedding=vector))
                if session.bind.dialect.name=='postgresql':
                    literal='['+','.join(str(v) for v in vector)+']'
                    session.execute(text('INSERT INTO product_image_ml_vectors(image_id,model_id,embedding) VALUES (:id,:model,CAST(:v AS vector))'),{'id':iid,'model':MODEL_ID,'v':literal})
        session.commit()
    except Exception as exc:
        session.rollback()
        for path in written:
            path.unlink(missing_ok=True)
        if isinstance(exc,HTTPException): raise
        logging.getLogger(__name__).exception("Photo indexing/upload failed")
        raise HTTPException(503,'Фотографии не сохранены: не удалось подготовить поисковый индекс. Повторите загрузку; подробности — в журнале сервера.') from exc
    finally:
        for f in files: f.file.close()
    session.expire_all()
    return serialize_product(get_product(session,pid))


@router.delete('/products/{pid}/images/{iid}')
def remove_image(pid: str, iid: str, session: Session = Depends(get_db)):
    product=get_product(session,pid)
    img=next((i for i in product.images if i.id==iid),None)
    if img is None: raise HTTPException(404,'Фотография не найдена')
    active=product.details.active if product.details else True
    if active and len(product.images)==1:
        raise HTTPException(409,'Сначала скройте товар или добавьте новую фотографию.')
    session.execute(delete(ImageMLEmbedding).where(ImageMLEmbedding.image_id==iid))
    if session.bind.dialect.name=='postgresql':
        for table in ('product_image_vectors','product_image_ml_vectors'):
            session.execute(text(f'DELETE FROM {table} WHERE image_id=:id'),{'id':iid})
    filename=img.filename
    session.delete(img); session.commit(); session.expire_all()
    if filename.startswith('uploads/'):
        (MEDIA/filename).unlink(missing_ok=True)
    return serialize_product(get_product(session,pid))
