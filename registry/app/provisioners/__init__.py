"""Interface base para provisioners por source_type."""

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class ProvisionResult:
    success: bool
    message: str
    progress: int = 100
    ollama_model_name: str | None = None
    estimated_vram_mb: int | None = None
    size_bytes: int | None = None


class ModelProvisioner(ABC):
    source_type: str

    @abstractmethod
    async def download(self, source_uri: str, purpose: str, on_progress=None) -> ProvisionResult:
        ...

    @abstractmethod
    async def verify(self, source_uri: str, purpose: str) -> ProvisionResult:
        ...
