"""Daily coarse-grained product interest counters (30-day retention in recommendations)."""
from sqlalchemy import Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class BuyerCategoryInterest(Base):
    __tablename__ = 'buyer_category_interests'
    buyer_id: Mapped[str] = mapped_column(
        String(32), ForeignKey('buyers.id', ondelete='CASCADE'), primary_key=True)
    category_id: Mapped[str] = mapped_column(String(80), primary_key=True)
    day: Mapped[int] = mapped_column(Integer, primary_key=True)
    views: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[float] = mapped_column(Float, nullable=False)
