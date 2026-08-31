"""Lógica de negócio do registry — CRUD, auditoria, limites."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import TenantContext
from app.base_models import is_base_model_name, load_base_models
from app.config import settings
from app.litellm_client import LiteLLMClient
from app.models_db import AuditLog, DynamicModel, utcnow
from app.schemas import ModelCreateRequest, ModelPatchRequest, ModelResponse
from app.security import SourceValidationError, validate_source_uri
from app.services.routing import build_litellm_route


class RegistryError(Exception):
    def __init__(self, message: str, code: str, status: int = 400):
        self.message = message
        self.code = code
        self.status = status
        super().__init__(message)


async def audit(db: AsyncSession, app_id: str, action: str, model_id: str | None = None, details: dict | None = None):
    db.add(AuditLog(app_id=app_id, model_id=model_id, action=action, details=details or {}))
    await db.flush()


def to_response(row: DynamicModel) -> ModelResponse:
    return ModelResponse(
        id=row.id,
        model_name=row.model_name,
        litellm_route=row.model_name,
        display_name=row.display_name,
        alias=row.alias,
        source_type=row.source_type,
        source_uri=row.source_uri,
        purpose=row.purpose,
        status=row.status,
        status_message=row.status_message,
        progress=row.progress,
        owner_app_id=row.owner_app_id,
        is_base=row.is_base,
        managed_by=row.managed_by,
        enabled=row.enabled,
        external_ref=row.external_ref,
        metadata=row.metadata_json,
        estimated_vram_mb=row.estimated_vram_mb,
        size_bytes=row.size_bytes,
        warm=row.warm,
        created_at=row.created_at,
        updated_at=row.updated_at,
        ready_at=row.ready_at,
    )


async def count_owned(db: AsyncSession, app_id: str) -> int:
    q = select(func.count()).select_from(DynamicModel).where(
        DynamicModel.owner_app_id == app_id,
        DynamicModel.status.notin_(["deleted"]),
    )
    return (await db.execute(q)).scalar_one()


async def count_downloading(db: AsyncSession) -> int:
    q = select(func.count()).select_from(DynamicModel).where(
        DynamicModel.status.in_(["queued", "downloading", "loading"])
    )
    return (await db.execute(q)).scalar_one()


async def get_model(db: AsyncSession, model_id: uuid.UUID) -> DynamicModel | None:
    return await db.get(DynamicModel, model_id)


async def create_model(
    db: AsyncSession,
    tenant: TenantContext,
    body: ModelCreateRequest,
    idempotency_key: str | None = None,
) -> DynamicModel:
    try:
        normalized_uri = validate_source_uri(body.source_type, body.source_uri)
    except SourceValidationError as exc:
        raise RegistryError(str(exc), "invalid_source_uri", 400) from exc

    if idempotency_key:
        existing = await db.execute(
            select(DynamicModel).where(
                DynamicModel.owner_app_id == tenant.app_id,
                DynamicModel.idempotency_key == idempotency_key,
            )
        )
        found = existing.scalar_one_or_none()
        if found:
            return found

    owned = await count_owned(db, tenant.app_id)
    if owned >= settings.max_models_per_tenant:
        raise RegistryError(
            f"limite de {settings.max_models_per_tenant} modelos por tenant atingido",
            "quota_exceeded",
            429,
        )

    downloading = await count_downloading(db)
    if downloading >= settings.max_concurrent_downloads:
        raise RegistryError(
            f"limite global de {settings.max_concurrent_downloads} downloads simultâneos",
            "download_quota_exceeded",
            429,
        )

    route = build_litellm_route(tenant.app_id, body.alias, normalized_uri)
    if is_base_model_name(route):
        raise RegistryError("nome colide com modelo base", "name_collision", 409)

    row = DynamicModel(
        model_name=route,
        display_name=body.display_name or body.alias or route,
        alias=body.alias,
        source_type=body.source_type,
        source_uri=normalized_uri,
        purpose=body.purpose,
        status="queued",
        progress=0,
        owner_app_id=tenant.app_id,
        managed_by="tenant",
        external_ref=body.external_ref,
        metadata_json=body.metadata,
        idempotency_key=idempotency_key,
    )
    db.add(row)
    await db.flush()
    await audit(db, tenant.app_id, "create", str(row.id), {"model_name": route})
    return row


async def patch_model(
    db: AsyncSession,
    tenant: TenantContext,
    row: DynamicModel,
    body: ModelPatchRequest,
) -> DynamicModel:
    _assert_owner(tenant, row)
    _assert_mutable(row)

    if body.display_name is not None:
        row.display_name = body.display_name
    if body.metadata is not None:
        row.metadata_json = {**(row.metadata_json or {}), **body.metadata}
    if body.enabled is not None:
        row.enabled = body.enabled
        if not body.enabled and row.status == "ready":
            row.status = "disabling"
        elif body.enabled and row.status == "disabled":
            row.status = "queued"  # re-queue for worker to re-register
    row.updated_at = utcnow()
    await audit(db, tenant.app_id, "update", str(row.id), body.model_dump(exclude_none=True))
    return row


async def delete_model(db: AsyncSession, tenant: TenantContext, row: DynamicModel) -> DynamicModel:
    _assert_owner(tenant, row)
    _assert_mutable(row)
    row.status = "deleting"
    row.updated_at = utcnow()
    await audit(db, tenant.app_id, "delete", str(row.id))
    return row


async def retry_model(db: AsyncSession, tenant: TenantContext, row: DynamicModel) -> DynamicModel:
    _assert_owner(tenant, row)
    _assert_mutable(row)
    if row.status != "failed":
        raise RegistryError("retry só permitido em status=failed", "invalid_state", 400)
    row.status = "queued"
    row.status_message = None
    row.progress = 0
    row.updated_at = utcnow()
    await audit(db, tenant.app_id, "retry", str(row.id))
    return row


async def warm_model(db: AsyncSession, tenant: TenantContext, row: DynamicModel) -> DynamicModel:
    _assert_owner(tenant, row)
    if row.status != "ready":
        raise RegistryError("warm só em modelos ready", "invalid_state", 400)
    row.warm = True
    row.updated_at = utcnow()
    await audit(db, tenant.app_id, "warm", str(row.id))
    return row


def _assert_owner(tenant: TenantContext, row: DynamicModel) -> None:
    if row.owner_app_id != tenant.app_id:
        raise RegistryError("modelo pertence a outro tenant", "forbidden", 403)


def _assert_mutable(row: DynamicModel) -> None:
    if row.is_base or row.managed_by == "system":
        raise RegistryError("modelos base são read-only", "base_model_immutable", 403)


async def list_models(db: AsyncSession, tenant: TenantContext) -> tuple[list[ModelResponse], list[ModelResponse]]:
    base = load_base_models()
    q = await db.execute(
        select(DynamicModel)
        .where(DynamicModel.owner_app_id == tenant.app_id)
        .where(DynamicModel.status != "deleted")
        .order_by(DynamicModel.created_at.desc())
    )
    owned = [to_response(r) for r in q.scalars().all()]
    return base, owned
