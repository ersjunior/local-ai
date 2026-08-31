"""Carrega modelos base do catálogo (config/models/*.yaml) — read-only."""

from pathlib import Path

import yaml

from app.config import settings
from app.schemas import ModelResponse


def load_base_models() -> list[ModelResponse]:
    catalog = Path(settings.catalog_path)
    if not catalog.is_dir():
        return []

    models: list[ModelResponse] = []
    for path in sorted(catalog.glob("*.yaml")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not data or not isinstance(data, dict):
            continue

        logical = data.get("logical_name")
        if not logical:
            continue

        models.append(
            ModelResponse(
                id=__import__("uuid").uuid5(__import__("uuid").NAMESPACE_DNS, f"base:{logical}"),
                model_name=logical,
                litellm_route=logical,
                display_name=data.get("logical_name"),
                source_type=data.get("backend", "system"),
                source_uri=data.get("model_id", ""),
                purpose=_backend_to_purpose(data.get("backend", "")),
                status="ready",
                owner_app_id=None,
                is_base=True,
                managed_by="system",
                enabled=data.get("enabled", True),
                metadata={"catalog_file": path.name, "license": data.get("license")},
            )
        )
    return models


def _backend_to_purpose(backend: str) -> str:
    mapping = {
        "ollama": "chat",
        "whisper": "transcribe",
        "localai": "image",
        "vllm": "chat",
    }
    return mapping.get(backend, "chat")


def is_base_model_name(name: str) -> bool:
    return any(m.model_name == name for m in load_base_models())
