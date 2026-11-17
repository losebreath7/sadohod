from sqlalchemy import Boolean, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .database import Base


class Pavilion(Base):
    __tablename__ = "pavilions"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    code: Mapped[str] = mapped_column(String(32))
    zone: Mapped[str] = mapped_column(String(160))


class Seller(Base):
    __tablename__ = "sellers"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    pavilion_id: Mapped[str] = mapped_column(ForeignKey("pavilions.id"))
    pavilion: Mapped[Pavilion] = relationship(lazy="joined")
    details: Mapped["SellerDetails | None"] = relationship(uselist=False, cascade="all, delete-orphan")


class Product(Base):
    __tablename__ = "products"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    title: Mapped[str] = mapped_column(String(160), index=True)
    category: Mapped[str] = mapped_column(String(80), index=True)
    description: Mapped[str] = mapped_column(Text)
    colors: Mapped[list] = mapped_column(JSON)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=True)
    details: Mapped["ProductDetails | None"] = relationship(uselist=False, cascade="all, delete-orphan")
    images: Mapped[list["ProductImage"]] = relationship(back_populates="product", cascade="all, delete-orphan")
    offers: Mapped[list["Offer"]] = relationship(back_populates="product", cascade="all, delete-orphan")
    category_assignment: Mapped["ProductCategoryAssignment | None"] = relationship(
        uselist=False, cascade="all, delete-orphan")


class Offer(Base):
    __tablename__ = "offers"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), index=True)
    seller_id: Mapped[str] = mapped_column(ForeignKey("sellers.id"), index=True)
    pavilion_id: Mapped[str] = mapped_column(ForeignKey("pavilions.id"))
    price: Mapped[int | None] = mapped_column(Integer, nullable=True)
    modes: Mapped["OfferSaleModes | None"] = relationship(uselist=False, cascade="all, delete-orphan", back_populates="offer")
    product: Mapped[Product] = relationship(back_populates="offers")
    seller: Mapped[Seller] = relationship(lazy="joined")
    pavilion: Mapped[Pavilion] = relationship(lazy="joined")


class OfferSaleModes(Base):
    """Optional metadata on an individual offer, not the shared product.

    An absent row means 'not specified' and must never be shown as a guessed
    retail/wholesale claim. Using an additive table avoids ALTER on old volumes.
    """
    __tablename__ = "offer_sale_modes"
    offer_id: Mapped[str] = mapped_column(ForeignKey("offers.id", ondelete="CASCADE"), primary_key=True)
    wholesale: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    retail: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    offer: Mapped[Offer] = relationship(back_populates="modes")


class ProductImage(Base):
    __tablename__ = "product_images"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), index=True)
    filename: Mapped[str] = mapped_column(String(80))
    ordering: Mapped["ImageOrder | None"] = relationship(uselist=False, cascade="all, delete-orphan")
    descriptor: Mapped[list] = mapped_column(JSON)  # fallback for local SQLite search
    product: Mapped[Product] = relationship(back_populates="images")


class ImageMLEmbedding(Base):
    """Portable JSON vectors; pgvector has a separate HNSW mirror."""
    __tablename__ = "image_ml_embeddings"
    image_id: Mapped[str] = mapped_column(ForeignKey("product_images.id", ondelete="CASCADE"), primary_key=True)
    model_id: Mapped[str] = mapped_column(String(140), primary_key=True)
    embedding: Mapped[list] = mapped_column(JSON, nullable=False)


class SellerDetails(Base):
    __tablename__ = "seller_details"
    seller_id: Mapped[str] = mapped_column(ForeignKey("sellers.id"), primary_key=True)
    contact: Mapped[str] = mapped_column(String(500), default="")
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)


class ProductDetails(Base):
    __tablename__ = "product_details"
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), primary_key=True)
    active: Mapped[bool] = mapped_column(Boolean, default=False)
    sizes: Mapped[list] = mapped_column(JSON, default=list)


class ImageOrder(Base):
    __tablename__ = "product_image_order"
    image_id: Mapped[str] = mapped_column(ForeignKey("product_images.id"), primary_key=True)
    position: Mapped[int] = mapped_column(Integer)
