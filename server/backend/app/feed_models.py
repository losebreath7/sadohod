"""First publication and bounded daily authenticated product engagement."""
from sqlalchemy import Boolean, Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from .database import Base


class FeedPublication(Base):
    __tablename__ = 'feed_publications'
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    published_at: Mapped[float] = mapped_column(Float, nullable=False)


class FeedView(Base):
    __tablename__ = 'feed_daily_views'
    __table_args__ = (Index('ix_feed_views_day', 'day'), Index('ix_feed_views_product', 'product_id'))
    buyer_id: Mapped[str] = mapped_column(ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    day: Mapped[int] = mapped_column(Integer, primary_key=True)
    engaged: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
