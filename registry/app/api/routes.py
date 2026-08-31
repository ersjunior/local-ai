"""Rotas HTTP /registry/v1."""

from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import AuthError, TenantContext, resolve_tenant
from app.config import settings
from app.database import get_db
from app.schemas import (
    CapabilitiesResponse,
    ErrorResponse,
    HealthResponse,
    ModelCreateRequest,
    ModelListResponse,
    ModelPatchRequest,
    ModelResponse,
)
from app.services import registry_service as svc
from app.services.routing import PURPOSE_LITELLM_MODE

router = APIRouter(prefix="/registry/v1", tags=["registry"])


async def get_tenant(authorization: str | None = Header(None)) -> TenantContext:
    try:
        return await resolve_tenant(authorization)
    except AuthError as exc:
        raise HTTPException(status_code=401, detail={"detail": exc.message, "code": exc.code}) from exc


def _http_error(exc: svc.RegistryError) -> HTTPException:
    return HTTPException(status_code=exc.status, detail={"detail": exc.message, "code": exc.code})


@router.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(status="ok")


@router.get("/capabilities", response_model=CapabilitiesResponse)
async def capabilities(_tenant: TenantContext = Depends(get_tenant)):
    return CapabilitiesResponse(
        source_types=["ollama", "huggingface", "other"],
        purposes=["chat", "vision", "transcribe", "image"],
        purpose_litellm_mapping=PURPOSE_LITELLM_MODE,
        limits={
            "max_models_per_tenant": settings.max_models_per_tenant,
            "max_concurrent_downloads": settings.max_concurrent_downloads,
        },
    )


@router.get("/models", response_model=ModelListResponse)
async def list_models(
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    base, owned = await svc.list_models(db, tenant)
    return ModelListResponse(base_models=base, owned_models=owned)


@router.post("/models", response_model=ModelResponse, status_code=202)
async def create_model(
    body: ModelCreateRequest,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    try:
        row = await svc.create_model(db, tenant, body, idempotency_key)
        await db.commit()
        await db.refresh(row)
        return svc.to_response(row)
    except svc.RegistryError as exc:
        raise _http_error(exc) from exc


@router.get("/models/{model_id}", response_model=ModelResponse)
async def get_model(
    model_id: UUID,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    row = await svc.get_model(db, model_id)
    if not row or row.status == "deleted":
        raise HTTPException(status_code=404, detail={"detail": "modelo não encontrado", "code": "not_found"})
    if row.is_base:
        raise HTTPException(status_code=404, detail={"detail": "use GET /models para base_models", "code": "not_found"})
    if row.owner_app_id != tenant.app_id:
        raise HTTPException(status_code=403, detail={"detail": "acesso negado", "code": "forbidden"})
    return svc.to_response(row)


@router.patch("/models/{model_id}", response_model=ModelResponse)
async def patch_model(
    model_id: UUID,
    body: ModelPatchRequest,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    row = await svc.get_model(db, model_id)
    if not row or row.status == "deleted":
        raise HTTPException(status_code=404, detail={"detail": "modelo não encontrado", "code": "not_found"})
    try:
        row = await svc.patch_model(db, tenant, row, body)
        await db.commit()
        await db.refresh(row)
        return svc.to_response(row)
    except svc.RegistryError as exc:
        raise _http_error(exc) from exc


@router.delete("/models/{model_id}", response_model=ModelResponse, status_code=202)
async def delete_model(
    model_id: UUID,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    row = await svc.get_model(db, model_id)
    if not row or row.status == "deleted":
        raise HTTPException(status_code=404, detail={"detail": "modelo não encontrado", "code": "not_found"})
    try:
        row = await svc.delete_model(db, tenant, row)
        await db.commit()
        await db.refresh(row)
        return svc.to_response(row)
    except svc.RegistryError as exc:
        raise _http_error(exc) from exc


@router.post("/models/{model_id}/retry", response_model=ModelResponse, status_code=202)
async def retry_model(
    model_id: UUID,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    row = await svc.get_model(db, model_id)
    if not row:
        raise HTTPException(status_code=404, detail={"detail": "modelo não encontrado", "code": "not_found"})
    try:
        row = await svc.retry_model(db, tenant, row)
        await db.commit()
        await db.refresh(row)
        return svc.to_response(row)
    except svc.RegistryError as exc:
        raise _http_error(exc) from exc


@router.post("/models/{model_id}/warm", response_model=ModelResponse, status_code=202)
async def warm_model(
    model_id: UUID,
    tenant: TenantContext = Depends(get_tenant),
    db: AsyncSession = Depends(get_db),
):
    row = await svc.get_model(db, model_id)
    if not row:
        raise HTTPException(status_code=404, detail={"detail": "modelo não encontrado", "code": "not_found"})
    try:
        row = await svc.warm_model(db, tenant, row)
        await db.commit()
        await db.refresh(row)
        return svc.to_response(row)
    except svc.RegistryError as exc:
        raise _http_error(exc) from exc
