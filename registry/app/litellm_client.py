"""Cliente HTTP para LiteLLM gateway — hot add/delete de rotas dinâmicas."""

import httpx

from app.config import settings


class LiteLLMClient:
    def __init__(self) -> None:
        self.base = settings.litellm_gateway_url.rstrip("/")
        self.master_key = settings.litellm_master_key

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.master_key}",
            "Content-Type": "application/json",
        }

    async def add_model(
        self,
        model_name: str,
        litellm_model: str,
        api_base: str,
        api_key: str = "dummy",
        mode: str = "chat",
        model_id: str | None = None,
        extra_model_info: dict | None = None,
    ) -> dict:
        payload: dict = {
            "model_name": model_name,
            "litellm_params": {
                "model": litellm_model,
                "api_base": api_base,
                "api_key": api_key,
            },
            "model_info": {
                "mode": mode,
                "id": model_id or model_name,
                **(extra_model_info or {}),
            },
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(f"{self.base}/model/new", headers=self._headers(), json=payload)
            resp.raise_for_status()
            return resp.json()

    async def delete_model(self, model_id: str) -> dict:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{self.base}/model/delete",
                headers=self._headers(),
                json={"id": model_id},
            )
            resp.raise_for_status()
            return resp.json()

    async def update_model(self, model_id: str, model_info: dict) -> dict:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{self.base}/model/update",
                headers=self._headers(),
                json={"model_id": model_id, "model_info": model_info},
            )
            resp.raise_for_status()
            return resp.json()
