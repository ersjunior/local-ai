"""Provisioner HuggingFace v1 — via Ollama hf.co/... (limitado)."""

from app.config import settings
from app.provisioners import ModelProvisioner, ProvisionResult
from app.provisioners.ollama import OllamaProvisioner
from app.security import parse_hf_repo


class HuggingFaceProvisioner(ModelProvisioner):
    """
  v1: tenta `ollama pull hf.co/{org}/{model}` para purposes chat/vision.
  Limitações documentadas em REGISTRY.md — image/transcribe podem falhar.
  """

    source_type = "huggingface"

    def __init__(self) -> None:
        self._ollama = OllamaProvisioner()

    def _to_ollama_ref(self, source_uri: str) -> str:
        repo = parse_hf_repo(source_uri)
        return f"ollama://hf.co/{repo}"

    async def download(self, source_uri: str, purpose: str, on_progress=None) -> ProvisionResult:
        if purpose in ("transcribe", "image"):
            return ProvisionResult(
                success=False,
                message=(
                    f"HF v1 não suporta purpose={purpose}; use source_type=ollama "
                    "ou aguarde provisioner dedicado"
                ),
            )
        ollama_uri = self._to_ollama_ref(source_uri)
        result = await self._ollama.download(ollama_uri, purpose, on_progress)
        if result.success:
            result.message = f"HF via Ollama: {result.message}"
        elif settings.huggingface_token:
            result.message += " (token HF configurado mas v1 usa apenas Ollama hf.co/)"
        return result

    async def verify(self, source_uri: str, purpose: str) -> ProvisionResult:
        return await self._ollama.verify(self._to_ollama_ref(source_uri), purpose)
