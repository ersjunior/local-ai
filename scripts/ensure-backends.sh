#!/usr/bin/env bash
# scripts/ensure-backends.sh
# Aguarda o backend diffusers OCI no container LocalAI (cuda12-diffusers).
# Uso: bash scripts/ensure-backends.sh
set -euo pipefail

IMAGES_CONTAINER="${IMAGES_CONTAINER:-localai-images}"
BACKEND_NAME="${LOCALAI_EXTERNAL_BACKENDS:-cuda12-diffusers}"
WAIT_SEC="${ENSURE_BACKENDS_WAIT_SEC:-300}"

log()  { printf '\033[1;34m[backends]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

if ! docker ps --format '{{.Names}}' | grep -q "^${IMAGES_CONTAINER}$"; then
  warn "container ${IMAGES_CONTAINER} não está rodando (perfil image inativo?)."
  exit 1
fi

log "Aguardando backend ${BACKEND_NAME} em /backends (até ${WAIT_SEC}s)..."
elapsed=0
while [ "$elapsed" -lt "$WAIT_SEC" ]; do
  if docker exec "$IMAGES_CONTAINER" test -d "/backends/${BACKEND_NAME}" 2>/dev/null; then
    log "backend ${BACKEND_NAME} presente em /backends."
    exit 0
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

warn "backend ${BACKEND_NAME} não instalado após ${WAIT_SEC}s."
warn "Verifique LOCALAI_EXTERNAL_BACKENDS=${BACKEND_NAME} no compose e os logs:"
warn "  docker compose logs images"
warn "Instalação manual (último recurso):"
warn "  docker exec ${IMAGES_CONTAINER} /local-ai backends install ${BACKEND_NAME}"
exit 1
