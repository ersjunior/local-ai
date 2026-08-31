"""Mapeamento purpose → LiteLLM mode + params de rota."""

PURPOSE_LITELLM_MODE = {
    "chat": "chat",
    "vision": "chat",
    "transcribe": "audio_transcription",
    "image": "image_generation",
}


def build_litellm_route(owner_app_id: str, alias: str | None, model_id: str) -> str:
    short = owner_app_id.replace("app-", "")[:8]
    slug = alias or model_id[:32].replace(":", "-").replace("/", "-")
    return f"dyn-{short}-{slug}"


def build_litellm_params(
    purpose: str,
    source_type: str,
    ollama_model_name: str | None,
    hf_repo: str | None = None,
) -> tuple[str, str, str]:
    """Retorna (litellm_model, api_base, mode)."""
    mode = PURPOSE_LITELLM_MODE.get(purpose, "chat")

    if source_type in ("ollama", "huggingface") and purpose in ("chat", "vision"):
        model = f"ollama_chat/{ollama_model_name}"
        from app.config import settings

        return model, f"{settings.ollama_url.rstrip('/')}", mode

    if purpose == "transcribe":
        return "openai/large-v3", "http://whisper:9000/v1", mode

    if purpose == "image":
        return "openai/flux-schnell", "http://images:8080/v1", mode

    model = f"ollama_chat/{ollama_model_name}"
    from app.config import settings

    return model, f"{settings.ollama_url.rstrip('/')}", mode
