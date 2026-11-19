"""Persistent moderation restrictions and transactional email dispatch receipts."""
import time

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, Text, Index
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class AccountRestriction(Base):
    __tablename__ = "moderation_account_restrictions"
    buyer_id: Mapped[str] = mapped_column(
        ForeignKey("buyers.id", ondelete="CASCADE"), primary_key=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    reason: Mapped[str] = mapped_column(Text, default="", nullable=False)
    until: Mapped[float | None] = mapped_column(Float, nullable=True)
    moderator_id: Mapped[str] = mapped_column(
        ForeignKey("moderator_users.id"), nullable=False)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)


class ShopRestriction(Base):
    __tablename__ = "moderation_shop_restrictions"
    seller_id: Mapped[str] = mapped_column(
        ForeignKey("sellers.id", ondelete="CASCADE"), primary_key=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    reason: Mapped[str] = mapped_column(Text, default="", nullable=False)
    until: Mapped[float | None] = mapped_column(Float, nullable=True)
    moderator_id: Mapped[str] = mapped_column(
        ForeignKey("moderator_users.id"), nullable=False)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)


class ModerationEmail(Base):
    __tablename__ = "moderation_email_outbox"
    __table_args__ = (Index('ix_moderation_email_due', 'status', 'next_attempt_at'),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    recipient: Mapped[str] = mapped_column(String(254), nullable=False)
    subject: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="pending", nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    next_attempt_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
    created_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
    sent_at: Mapped[float | None] = mapped_column(Float, nullable=True)
