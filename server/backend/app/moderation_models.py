"""Moderation staff, revocable sessions and an auditable decision trail."""
import time
from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from .database import Base


class ModeratorUser(Base):
    __tablename__ = 'moderator_users'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(80), nullable=False)
    secret_digest: Mapped[str] = mapped_column(String(160), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)


class ModeratorSession(Base):
    __tablename__ = 'moderator_sessions'
    digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    moderator_id: Mapped[str] = mapped_column(ForeignKey('moderator_users.id', ondelete='CASCADE'), index=True, nullable=False)
    expires_at: Mapped[float] = mapped_column(Float, nullable=False)


class ModerationAction(Base):
    __tablename__ = 'moderation_actions'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    moderator_id: Mapped[str] = mapped_column(ForeignKey('moderator_users.id'), index=True, nullable=False)
    kind: Mapped[str] = mapped_column(String(24), nullable=False)
    target_id: Mapped[str] = mapped_column(String(32), nullable=False)
    decision: Mapped[str] = mapped_column(String(24), nullable=False)
    note: Mapped[str] = mapped_column(Text, default='', nullable=False)
    created_at: Mapped[float] = mapped_column(Float, default=time.time, nullable=False)
