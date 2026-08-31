"""Schemas Pydantic — contrato JSON estável da API."""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, HttpUrl

SourceType = Literal["ollama", "huggingface", "other"]
Purpose = Literal["chat", "vision", "transcribe", "image"]
ModelStatus = Literal[
    "queued", "downloading", "loading", "ready",
    "failed", "disabling", "disabled", "deleting", "deleted",
]


class ErrorResponse(BaseModel):
    detail: str
    code: str


class ModelCreateRequest(BaseModel):
    source_type: SourceType
    source_uri: str = Field(..., min_length=1, max_length=2048)
    purpose: Purpose
    display_name: str | None = Field(None, max_length=256)
    alias: str | None = Field(None, max_length=64, pattern=r"^[a-z0-9][a-z0-9_-]{1,62}$")
    external_ref: str | None = Field(None, max_length=256)
    metadata: dict[str, Any] | None = None


class ModelPatchRequest(BaseModel):
    display_name: str | None = Field(None, max_length=256)
    alias: str | None = Field(None, max_length=64, pattern=r"^[a-z0-9][a-z0-9_-]{1,62}$")
    enabled: bool | None = None
    metadata: dict[str, Any] | None = None


class ModelResponse(BaseModel):
    id: UUID
    model_name: str
    litellm_route: str
    display_name: str | None = None
    alias: str | None = None
    source_type: str
    source_uri: str
    purpose: str
    status: str
    status_message: str | None = None
    progress: int | None = None
    owner_app_id: str | None = None
    is_base: bool = False
    managed_by: str = "tenant"
    enabled: bool = True
    external_ref: str | None = None
    metadata: dict[str, Any] | None = None
    estimated_vram_mb: int | None = None
    size_bytes: int | None = None
    warm: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None
    ready_at: datetime | None = None

    model_config = {"from_attributes": True}


class ModelListResponse(BaseModel):
    base_models: list[ModelResponse]
    owned_models: list[ModelResponse]


class CapabilitiesResponse(BaseModel):
    source_types: list[str]
    purposes: list[str]
    purpose_litellm_mapping: dict[str, str]
    limits: dict[str, int]


class HealthResponse(BaseModel):
    status: str
    version: str = "1.0.0"
