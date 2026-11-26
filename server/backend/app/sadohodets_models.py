"""Independent courier profiles and private client collections."""
from sqlalchemy import Boolean, CheckConstraint, Float, ForeignKey, Index, Integer, JSON, LargeBinary, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from .database import Base


class SadohodetsProfile(Base):
    __tablename__ = 'sadohodets_profiles'
    __table_args__ = (Index('ix_sadohodets_directory', 'published', 'last_active_at'),)
    buyer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text, default='')
    contacts: Mapped[dict] = mapped_column(JSON, default=dict)
    avatar: Mapped[str | None] = mapped_column(String(500))
    cover: Mapped[str | None] = mapped_column(String(500))
    published: Mapped[bool] = mapped_column(Boolean, default=False)
    last_active_at: Mapped[float] = mapped_column(Float)
    created_at: Mapped[float] = mapped_column(Float)


class SadohodetsFolder(Base):
    __tablename__ = 'sadohodets_folders'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), index=True)
    name: Mapped[str] = mapped_column(String(120))
    note: Mapped[str] = mapped_column(Text, default='')
    client_link: Mapped[str] = mapped_column(String(2048), default='', server_default='')
    created_at: Mapped[float] = mapped_column(Float)


class SadohodetsFolderItem(Base):
    __tablename__ = 'sadohodets_folder_items'
    __table_args__ = (CheckConstraint('quantity >= 1 AND quantity <= 999', name='ck_sadohodets_item_quantity'),)
    folder_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_folders.id', ondelete='CASCADE'), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    note: Mapped[str] = mapped_column(String(250), default='', server_default='')
    collected: Mapped[bool] = mapped_column(Boolean, default=False)
    quantity: Mapped[int] = mapped_column(Integer, default=1, server_default='1')
    added_at: Mapped[float] = mapped_column(Float)


class SadohodetsReview(Base):
    __tablename__ = 'sadohodets_reviews'
    __table_args__ = (
        CheckConstraint('rating >= 1 AND rating <= 5', name='ck_sadohodets_review_rating'),
        CheckConstraint('profile_id <> reviewer_id', name='ck_sadohodets_review_not_self'),
        Index('ix_sadohodets_reviews_status', 'moderation_status'),
    )
    profile_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), primary_key=True)
    reviewer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    rating: Mapped[int] = mapped_column(Integer)
    body: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[float] = mapped_column(Float)
    moderation_status: Mapped[str] = mapped_column(String(16), default='pending', server_default='pending')


class SadohodetsMedia(Base):
    __tablename__ = 'sadohodets_media'
    profile_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), primary_key=True)
    kind: Mapped[str] = mapped_column(String(8), primary_key=True)
    raw: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
