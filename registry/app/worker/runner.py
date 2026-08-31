"""Worker — processa jobs assíncronos (pull, load, register LiteLLM, delete)."""

import asyncio
import logging

from sqlalchemy import select

from app.config import settings
from app.database import SessionLocal, init_db
from app.litellm_client import LiteLLMClient
from app.models_db import DynamicModel, utcnow
from app.provisioners.huggingface import HuggingFaceProvisioner
from app.provisioners.ollama import OllamaProvisioner
from app.security import parse_hf_repo, parse_ollama_model
from app.services.routing import build_litellm_params

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("registry.worker")

PROVISIONERS = {
    "ollama": OllamaProvisioner(),
    "huggingface": HuggingFaceProvisioner(),
}


async def process_one(row: DynamicModel, litellm: LiteLLMClient) -> None:
    async with SessionLocal() as db:
        row = await db.get(DynamicModel, row.id)
        if not row:
            return

        if row.status == "queued":
            row.status = "downloading"
            row.updated_at = utcnow()
            await db.commit()

        if row.status == "downloading":
            provisioner = PROVISIONERS.get(row.source_type)
            if not provisioner:
                row.status = "failed"
                row.status_message = f"source_type '{row.source_type}' sem provisioner"
                await db.commit()
                return

            async def on_progress(pct: int, msg: str):
                row.progress = pct
                row.status_message = msg
                row.updated_at = utcnow()
                await db.commit()

            result = await provisioner.download(row.source_uri, row.purpose, on_progress)
            if not result.success:
                row.status = "failed"
                row.status_message = result.message
                await db.commit()
                return

            row.status = "loading"
            row.progress = result.progress or 100
            row.estimated_vram_mb = result.estimated_vram_mb
            row.size_bytes = result.size_bytes
            await db.commit()

        if row.status == "loading":
            try:
                ollama_name = parse_ollama_model(row.source_uri)
                if row.source_type == "huggingface":
                    ollama_name = parse_ollama_model(f"ollama://hf.co/{parse_hf_repo(row.source_uri)}")

                litellm_model, api_base, mode = build_litellm_params(
                    row.purpose, row.source_type, ollama_name
                )
                extra = {"metadata": {"registry_id": str(row.id), "owner_app_id": row.owner_app_id}}
                if row.purpose == "vision":
                    extra["supports_vision"] = True

                resp = await litellm.add_model(
                    model_name=row.model_name,
                    litellm_model=litellm_model,
                    api_base=api_base,
                    mode=mode,
                    model_id=str(row.id),
                    extra_model_info=extra,
                )
                row.litellm_model_id = resp.get("model_id") or str(row.id)
                row.status = "ready"
                row.ready_at = utcnow()
                row.status_message = "registrado no LiteLLM"
                row.progress = 100
            except Exception as exc:
                row.status = "failed"
                row.status_message = f"LiteLLM register: {exc}"
            row.updated_at = utcnow()
            await db.commit()

        if row.status == "deleting":
            try:
                if row.litellm_model_id:
                    await litellm.delete_model(row.litellm_model_id)
            except Exception as exc:
                log.warning("delete litellm %s: %s", row.litellm_model_id, exc)
            row.status = "deleted"
            row.updated_at = utcnow()
            await db.commit()

        if row.status == "disabling":
            try:
                if row.litellm_model_id:
                    await litellm.delete_model(row.litellm_model_id)
            except Exception as exc:
                log.warning("disable litellm %s: %s", row.litellm_model_id, exc)
            row.status = "disabled"
            row.litellm_model_id = None
            row.updated_at = utcnow()
            await db.commit()


async def poll_loop() -> None:
    await init_db()
    litellm = LiteLLMClient()
    log.info("worker iniciado (poll=%ss)", settings.worker_poll_interval_sec)

    while True:
        async with SessionLocal() as db:
            q = await db.execute(
                select(DynamicModel).where(
                    DynamicModel.status.in_(
                        ["queued", "downloading", "loading", "deleting", "disabling"]
                    )
                ).limit(settings.max_concurrent_downloads)
            )
            jobs = list(q.scalars().all())

        for job in jobs:
            try:
                await process_one(job, litellm)
            except Exception:
                log.exception("erro processando %s", job.id)

        await asyncio.sleep(settings.worker_poll_interval_sec)


def main() -> None:
    asyncio.run(poll_loop())


if __name__ == "__main__":
    main()
