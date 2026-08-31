"""Autenticação via virtual key LiteLLM → tenant (owner_app_id)."""

import hashlib
from dataclasses import dataclass

import httpx

from app.config import settings


@dataclass
class TenantContext:
    app_id: str
    token: str
    key_hash: str
    metadata: dict
    allowed_models: list[str] | None


class AuthError(Exception):
    def __init__(self, message: str, code: str = "unauthorized"):
        self.message = message
        self.code = code
        super().__init__(message)


async def resolve_tenant(authorization: str | None) -> TenantContext:
    if not authorization or not authorization.startswith("Bearer "):
        raise AuthError("Authorization: Bearer <virtual-key> obrigatório", "missing_token")

    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise AuthError("Token vazio", "missing_token")

    # Master key não é aceita para operações de tenant (só virtual keys)
    if token == settings.litellm_master_key:
        raise AuthError(
            "Master key não pode ser usada no registry; use uma virtual key de app",
            "master_key_forbidden",
        )

    key_hash = hashlib.sha256(token.encode()).hexdigest()[:16]

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(
            f"{settings.litellm_gateway_url}/key/info",
            headers={"Authorization": f"Bearer {token}"},
        )

    if resp.status_code == 401:
        raise AuthError("Virtual key inválida ou expirada", "invalid_key")
    if resp.status_code != 200:
        raise AuthError(f"Falha ao validar key: HTTP {resp.status_code}", "key_validation_failed")

    data = resp.json()
    info = data.get("info") or data
    metadata = info.get("metadata") or {}

    # Tenant = app_id explícito > project > hash da key
    app_id = (
        metadata.get("app_id")
        or metadata.get("project")
        or info.get("team_id")
        or f"app-{key_hash}"
    )

    models = info.get("models")
    if models == ["all-proxy-models"] or models == ["all-team-models"]:
        models = None

    return TenantContext(
        app_id=str(app_id),
        token=token,
        key_hash=key_hash,
        metadata=metadata,
        allowed_models=models,
    )
