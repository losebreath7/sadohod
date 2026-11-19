"""Buyer-only seller notes and optional seller reviews, additive v0.8.2 tables.

Never modifies merchant catalog records; buyer notes are not public. Reviews
are user opinions, NOT verified-purchase statements.
"""
import base64
import binascii
import io
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Float, ForeignKey, Integer, JSON, String, Text, UniqueConstraint, delete, func, select
from sqlalchemy.orm import Mapped, Session, mapped_column
from PIL import Image, ImageOps, UnidentifiedImageError

from .account import Buyer, current_buyer
from .admin_auth import require_admin
from .database import Base, get_db
from .models import Seller

router = APIRouter(prefix='/api/v1', tags=['Buyer seller notes and reviews'])

class BuyerSellerNote(Base):
    __tablename__ = 'buyer_seller_notes_v082'
    buyer: Mapped[str] = mapped_column(ForeignKey('buyers.id'), primary_key=True)
    seller: Mapped[str] = mapped_column(ForeignKey('sellers.id'), primary_key=True)
    text: Mapped[str] = mapped_column(String(100), default='')

class SellerReview(Base):
    __tablename__ = 'seller_reviews_v082'
    __table_args__ = (UniqueConstraint('buyer', 'seller', name='uq_v082_review_one_per_buyer'),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer: Mapped[str] = mapped_column(ForeignKey('buyers.id'), index=True)
    seller: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(Text, default='')
    photos: Mapped[list] = mapped_column(JSON, default=list)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    moderation_status: Mapped[str] = mapped_column(String(16), default='pending', nullable=False)
    reply: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time)

class ReviewReport(Base):
    __tablename__ = 'seller_review_reports_v082'
    __table_args__ = (UniqueConstraint('buyer', 'review_id', name='uq_v082_review_report'),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer: Mapped[str] = mapped_column(ForeignKey('buyers.id'), index=True)
    review_id: Mapped[str] = mapped_column(ForeignKey('seller_reviews_v082.id'), index=True)
    reason: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    resolved_at: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    resolution: Mapped[str] = mapped_column(String(16), default='', nullable=False)

class NoteInput(BaseModel):
    text: str = Field(max_length=100)

class ReviewInput(BaseModel):
    rating: int = Field(ge=1, le=5)
    text: str = Field(default='', max_length=2000)
    photos: list[str] = Field(default_factory=list, max_length=3)

class ReportInput(BaseModel):
    reason: str = Field(min_length=4, max_length=200)

class ReplyInput(BaseModel):
    text: str = Field(min_length=1, max_length=1000)

class ModerationInput(BaseModel):
    hidden: bool


def require_seller(db: Session, seller_id: str):
    if len(seller_id) > 32 or not db.get(Seller, seller_id):
        raise HTTPException(404, 'Продавец не найден')


def clean_photos(photos: list[str]) -> list[str]:
    output = []
    for encoded in photos:
        if len(encoded) > 650000:
            raise HTTPException(413, 'Фотография слишком большая')
        try:
            buf = base64.b64decode(encoded, validate=True)
            with Image.open(io.BytesIO(buf)) as im:
                if im.format not in {'JPEG', 'PNG', 'WEBP'}:
                    raise ValueError('Format')
                im = ImageOps.exif_transpose(im)
                im.thumbnail((900, 900))
                target = io.BytesIO()
                im.convert('RGB').save(target, format='JPEG', quality=72)
                output.append(base64.b64encode(target.getvalue()).decode('ascii'))
        except (ValueError, binascii.Error, OSError, UnidentifiedImageError, Image.DecompressionBombError):
            raise HTTPException(422, 'Некорректная фотография отзыва') from None
    return output

@router.get('/sellers/{seller_id}/my-note')
def my_note(seller_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    require_seller(db, seller_id)
    note = db.get(BuyerSellerNote, (buyer.id, seller_id))
    return {'text': note.text if note else ''}

@router.post('/sellers/{seller_id}/my-note')
def save_note(seller_id: str, body: NoteInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    require_seller(db, seller_id)
    row = db.get(BuyerSellerNote, (buyer.id, seller_id))
    if row is None:
        row = BuyerSellerNote(buyer=buyer.id, seller=seller_id, text='')
        db.add(row)
    row.text = body.text.strip()
    db.commit()
    return {'text': row.text}


def view(review, db):
    author = db.get(Buyer, review.buyer)
    return {'id':review.id, 'seller_id':review.seller, 'rating':review.rating,
            'text':review.text, 'photos':review.photos or [],
            'name':author.name.strip() if author and author.name.strip() else 'Пользователь',
            'reply':review.reply, 'created_at':review.created_at,
            'moderation_status':review.moderation_status}

@router.get('/sellers/{seller_id}/reviews')
def list_reviews(seller_id: str, db: Session = Depends(get_db)):
    require_seller(db, seller_id)
    rows = db.scalars(select(SellerReview).where(
        SellerReview.seller == seller_id, SellerReview.hidden.is_(False),
        SellerReview.moderation_status == 'approved')
        .order_by(SellerReview.created_at.desc())).all()
    return {'count':len(rows),
            'average':round(sum(row.rating for row in rows)/len(rows), 2) if rows else None,
            'items':[view(row,db) for row in rows], 'verified_purchases':False}

@router.get('/sellers/{seller_id}/my-review')
def my_review(seller_id: str, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    require_seller(db, seller_id)
    review=db.scalar(select(SellerReview).where(SellerReview.seller==seller_id,SellerReview.buyer==buyer.id))
    return {'item':view(review,db) if review else None, 'hidden':bool(review.hidden) if review else False}

@router.post('/sellers/{seller_id}/reviews')
def upsert_review(seller_id: str, body: ReviewInput, buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    require_seller(db, seller_id)
    row=db.scalar(select(SellerReview).where(SellerReview.seller==seller_id,SellerReview.buyer==buyer.id))
    if row is None:
        row=SellerReview(id=secrets.token_hex(16),buyer=buyer.id,seller=seller_id,
                         rating=body.rating,text='',photos=[])
        db.add(row)
    if row.hidden:
        raise HTTPException(403, 'Отзыв скрыт модератором. Обратитесь в поддержку.')
    row.rating=body.rating
    row.text=body.text.strip()
    row.photos=clean_photos(body.photos)
    row.updated_at=time.time()
    # Editing an approved review returns it to moderation.
    row.moderation_status = 'pending'
    row.reply = ''
    db.commit()
    return {'saved':True, 'item':view(row,db)}

@router.post('/sellers/{seller_id}/reviews/{review_id}/report')
def report_review(seller_id: str, review_id: str, body: ReportInput,
                  buyer: Buyer = Depends(current_buyer), db: Session = Depends(get_db)):
    row=db.get(SellerReview, review_id)
    if row is None or row.seller != seller_id or row.hidden or row.moderation_status != 'approved':
        raise HTTPException(404, 'Отзыв не найден')
    if row.buyer == buyer.id:
        raise HTTPException(403, 'Нельзя пожаловаться на собственный отзыв')
    already=db.scalar(select(ReviewReport).where(ReviewReport.buyer==buyer.id,ReviewReport.review_id==review_id))
    if already:
        return {'saved':True}
    db.add(ReviewReport(id=secrets.token_hex(16),buyer=buyer.id,review_id=review_id,reason=body.reason.strip()))
    db.commit()
    return {'saved':True}

@router.post('/merchant/reviews/{review_id}/reply')
def reply_review(review_id: str, body: ReplyInput, buyer: Buyer = Depends(current_buyer),db: Session = Depends(get_db)):
    from .merchant import shop_for
    shop=shop_for(buyer,db)
    row=db.get(SellerReview,review_id)
    if row is None or row.seller!=shop.id or row.hidden or row.moderation_status != 'approved':
        raise HTTPException(404,'Отзыв не найден')
    row.reply=body.text.strip()
    row.updated_at=time.time()
    db.commit()
    return {'saved':True}

@router.get('/admin/reviews/reports', dependencies=[Depends(require_admin)])
def reports(db: Session = Depends(get_db)):
    rows=db.scalars(select(ReviewReport).order_by(ReviewReport.created_at.desc()).limit(200)).all()
    return {'items':[{'id':r.id,'review_id':r.review_id,'reason':r.reason,'created_at':r.created_at} for r in rows]}

@router.post('/admin/reviews/{review_id}/moderate', dependencies=[Depends(require_admin)])
def moderate(review_id: str, body: ModerationInput, db: Session=Depends(get_db)):
    row=db.get(SellerReview,review_id)
    if row is None:
        raise HTTPException(404,'Отзыв не найден')
    row.hidden=body.hidden
    db.commit()
    return {'saved':True,'hidden':row.hidden}
