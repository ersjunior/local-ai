"""Entrypoint FastAPI."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router
from app.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="local-ai Model Registry",
    description="API de gestão de modelos dinâmicos multi-tenant",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/registry/docs",
    openapi_url="/registry/openapi.json",
    redoc_url="/registry/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
