"""Independent courier profiles and private client collections."""
from sqlalchemy import Boolean, CheckConstraint, Float, ForeignKey, Index, Integer, JSON, String, Text
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
    created_at: Mapped[float] = mapped_column(Float)


class SadohodetsFolderItem(Base):
    __tablename__ = 'sadohodets_folder_items'
    folder_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_folders.id', ondelete='CASCADE'), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    collected: Mapped[bool] = mapped_column(Boolean, default=False)
    added_at: Mapped[float] = mapped_column(Float)


class SadohodetsReview(Base):
    __tablename__ = 'sadohodets_reviews'
    __table_args__ = (
        CheckConstraint('rating >= 1 AND rating <= 5', name='ck_sadohodets_review_rating'),
        CheckConstraint('profile_id <> reviewer_id', name='ck_sadohodets_review_not_self'),
    )
    profile_id: Mapped[str] = mapped_column(ForeignKey('sadohodets_profiles.buyer_id', ondelete='CASCADE'), primary_key=True)
    reviewer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    rating: Mapped[int] = mapped_column(Integer)
    body: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[float] = mapped_column(Float)
