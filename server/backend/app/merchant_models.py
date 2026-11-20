"""v0.8 additive merchant workflow: never replaces legacy buyer or catalog tables."""
import time
from sqlalchemy import Boolean, ForeignKey, Integer, String, Text, Float, UniqueConstraint, JSON
from sqlalchemy.orm import Mapped, mapped_column
from .database import Base


def now():
    return time.time()


class MerchantOperation(Base):
    """Atomic retry receipts, scoped to one seller. Added without ALTER TABLE."""
    __tablename__ = 'merchant_operations'
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), primary_key=True)
    request_id: Mapped[str] = mapped_column(String(80), primary_key=True)
    digest: Mapped[str] = mapped_column(String(64))
    result: Mapped[dict] = mapped_column(JSON)


class ProductCategoryState(Base):
    __tablename__ = 'product_category_state'
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id'), primary_key=True)
    source: Mapped[str] = mapped_column(String(24), default='unknown')
    status: Mapped[str] = mapped_column(String(32), default='needs_review')
    assigned: Mapped[str] = mapped_column(String(80), default='Без категории')
    suggestion: Mapped[str] = mapped_column(String(80), default='')
    score: Mapped[float] = mapped_column(Float, default=0.0)


class ShopApplication(Base):
    __tablename__ = 'merchant_applications'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    buyer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), index=True)
    shop_name: Mapped[str] = mapped_column(String(120))
    contact: Mapped[str] = mapped_column(String(250), default='')
    zone: Mapped[str] = mapped_column(String(160))
    code: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(16), default='pending', index=True)
    note: Mapped[str] = mapped_column(Text, default='')
    seller_id: Mapped[str | None] = mapped_column(ForeignKey('sellers.id'), nullable=True)
    created_at: Mapped[float] = mapped_column(Float, default=now)


class ShopMembership(Base):
    __tablename__ = 'merchant_memberships'
    buyer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    role: Mapped[str] = mapped_column(String(12), default='owner')


class ShopRecord(Base):
    __tablename__ = 'merchant_shops'
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), primary_key=True)
    approved_at: Mapped[float] = mapped_column(Float, default=now)


class PavilionClaim(Base):
    """Unique approved physical trading place; also links many locations to a shop."""
    __tablename__ = 'merchant_pavilion_claims'
    zone_key: Mapped[str] = mapped_column(String(160), primary_key=True)
    code_key: Mapped[str] = mapped_column(String(32), primary_key=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    pavilion_id: Mapped[str] = mapped_column(ForeignKey('pavilions.id'), unique=True)
    approved_at: Mapped[float] = mapped_column(Float, default=now)


class PavilionRequest(Base):
    __tablename__ = 'merchant_pavilion_requests'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    zone: Mapped[str] = mapped_column(String(160))
    code: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(16), default='pending')
    note: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[float] = mapped_column(Float, default=now)


class MerchantProduct(Base):
    __tablename__ = 'merchant_products'
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id'), primary_key=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    status: Mapped[str] = mapped_column(String(16), default='draft', index=True)
    note: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[float] = mapped_column(Float, default=now)


class MerchantListing(Base):
    __tablename__ = 'merchant_listings'
    __table_args__ = (UniqueConstraint('product_id', 'pavilion_id', name='uq_merchant_product_pavilion'),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id'), index=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey('sellers.id'), index=True)
    pavilion_id: Mapped[str] = mapped_column(ForeignKey('pavilions.id'))
    price: Mapped[int | None] = mapped_column(Integer, nullable=True)
    wholesale: Mapped[bool] = mapped_column(Boolean, default=False)
    retail: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(16), default='draft')
    offer_id: Mapped[str | None] = mapped_column(ForeignKey('offers.id'), unique=True, nullable=True)
    note: Mapped[str] = mapped_column(Text, default='')


class MerchantInvitation(Base):
    __tablename__ = 'merchant_invitations'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    code_digest: Mapped[str] = mapped_column(String(64), unique=True)
    email: Mapped[str] = mapped_column(String(254), index=True)
    shop_name: Mapped[str] = mapped_column(String(120))
    contact: Mapped[str] = mapped_column(String(250), default='')
    zone: Mapped[str] = mapped_column(String(160))
    code: Mapped[str] = mapped_column(String(32))
    expires_at: Mapped[float] = mapped_column(Float)
    used_at: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[float] = mapped_column(Float, default=now)


class CatalogCategory(Base):
    """Stable taxonomy node; parent link never mutates a published product."""
    __tablename__ = 'catalog_categories'
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    parent_id: Mapped[str | None] = mapped_column(
        ForeignKey('catalog_categories.id'), nullable=True, index=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)


class ProductCategoryAssignment(Base):
    """One precise category per product; all ancestors are derived at query time."""
    __tablename__ = 'product_category_assignments'
    product_id: Mapped[str] = mapped_column(
        ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    category_id: Mapped[str] = mapped_column(
        ForeignKey('catalog_categories.id'), nullable=False, index=True)
    source: Mapped[str] = mapped_column(String(24), nullable=False)


class ProductSearchTag(Base):
    """A verified/searchable facet; not another category or seller-supplied claim.

    Tags remain independent from the single primary taxonomy path, allowing
    multiple search terms for an item without changing category filters.
    Reclassification replaces only model-derived tags for this product.
    """
    __tablename__ = 'product_search_tags'
    product_id: Mapped[str] = mapped_column(
        ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    tag: Mapped[str] = mapped_column(String(80), primary_key=True, index=True)
    source: Mapped[str] = mapped_column(String(24), nullable=False)
