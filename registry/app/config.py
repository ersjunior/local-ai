"""Configuração do registry (env vars)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # API
    registry_host: str = "0.0.0.0"
    registry_port: int = 4010
    catalog_path: str = "/catalog"

    # Postgres (database dedicado do registry)
    registry_database_url: str = "postgresql+asyncpg://registry:registry@postgres:5432/registry"

    # LiteLLM gateway
    litellm_gateway_url: str = "http://gateway:4000"
    litellm_master_key: str = ""

    # Backends
    ollama_url: str = "http://ollama:11434"
    images_url: str = "http://images:8080"
    huggingface_token: str = ""

    # Redis (idempotency + worker coordination)
    redis_url: str = "redis://redis:6379/0"

    # Limites por tenant
    max_models_per_tenant: int = 10
    max_concurrent_downloads: int = 2

    # Worker
    worker_poll_interval_sec: float = 3.0
    ollama_pull_timeout_sec: int = 1800


settings = Settings()
