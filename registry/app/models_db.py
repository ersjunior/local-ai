"""Modelos SQLAlchemy — dynamic_models + audit_log."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import BigInteger, Boolean, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class DynamicModel(Base):
    __tablename__ = "dynamic_models"
    __table_args__ = (
        UniqueConstraint("owner_app_id", "alias", name="uq_owner_alias"),
        UniqueConstraint("owner_app_id", "idempotency_key", name="uq_owner_idempotency"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    model_name: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(256), nullable=True)
    alias: Mapped[str | None] = mapped_column(String(64), nullable=True)
    source_type: Mapped[str] = mapped_column(String(32))
    source_uri: Mapped[str] = mapped_column(Text)
    purpose: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), default="queued", index=True)
    status_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    progress: Mapped[int | None] = mapped_column(Integer, nullable=True)
    owner_app_id: Mapped[str] = mapped_column(String(128), index=True)
    litellm_model_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_base: Mapped[bool] = mapped_column(Boolean, default=False)
    managed_by: Mapped[str] = mapped_column(String(32), default="tenant")  # system | tenant
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    external_ref: Mapped[str | None] = mapped_column(String(256), nullable=True)
    metadata_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    estimated_vram_mb: Mapped[int | None] = mapped_column(Integer, nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    warm: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    ready_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True)


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    app_id: Mapped[str] = mapped_column(String(128), index=True)
    model_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    action: Mapped[str] = mapped_column(String(64))
    details: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
