"""Provisioner Ollama — ollama pull via API HTTP."""

import json

import httpx

from app.config import settings
from app.provisioners import ModelProvisioner, ProvisionResult
from app.security import parse_ollama_model


class OllamaProvisioner(ModelProvisioner):
    source_type = "ollama"

    async def download(self, source_uri: str, purpose: str, on_progress=None) -> ProvisionResult:
        model = parse_ollama_model(source_uri)
        url = f"{settings.ollama_url.rstrip('/')}/api/pull"
        try:
            async with httpx.AsyncClient(timeout=settings.ollama_pull_timeout_sec) as client:
                async with client.stream("POST", url, json={"name": model, "stream": True}) as resp:
                    if resp.status_code != 200:
                        body = await resp.aread()
                        return ProvisionResult(
                            success=False,
                            message=f"ollama pull falhou: HTTP {resp.status_code} {body.decode()[:200]}",
                        )
                    last_status = ""
                    progress = 0
                    async for line in resp.aiter_lines():
                        if not line:
                            continue
                        try:
                            chunk = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if "status" in chunk:
                            last_status = chunk["status"]
                        if "completed" in chunk and "total" in chunk and chunk["total"]:
                            progress = int(chunk["completed"] / chunk["total"] * 100)
                            if on_progress:
                                await on_progress(progress, last_status)
                    return ProvisionResult(
                        success=True,
                        message=last_status or "pull concluído",
                        progress=100,
                        ollama_model_name=model,
                    )
        except httpx.TimeoutException:
            return ProvisionResult(success=False, message="timeout no ollama pull")
        except Exception as exc:
            return ProvisionResult(success=False, message=str(exc))

    async def verify(self, source_uri: str, purpose: str) -> ProvisionResult:
        model = parse_ollama_model(source_uri)
        url = f"{settings.ollama_url.rstrip('/')}/api/tags"
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            tags = resp.json().get("models", [])
            names = {t.get("name", "").split(":")[0] for t in tags}
            full_names = {t.get("name", "") for t in tags}
            base = model.split(":")[0]
            if model in full_names or base in names:
                return ProvisionResult(success=True, message="modelo disponível", ollama_model_name=model)
            return ProvisionResult(success=False, message=f"modelo '{model}' não encontrado no Ollama")
