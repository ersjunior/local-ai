#!/usr/bin/env bash
# scripts/pull-models.sh
# Baixa os pesos dos modelos e cria os aliases lógicos do Ollama.
# Uso: bash scripts/pull-models.sh
set -euo pipefail

OLLAMA_CONTAINER="${OLLAMA_CONTAINER:-localai-ollama}"
IMAGES_CONTAINER="${IMAGES_CONTAINER:-localai-images}"

log()  { printf '\033[1;34m[pull]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# --- Ollama: LLMs + VLM ----------------------------------------------------
log "Baixando modelos do Ollama (isso pode demorar)..."
docker exec "$OLLAMA_CONTAINER" ollama pull qwen3:32b
docker exec "$OLLAMA_CONTAINER" ollama pull qwen3-vl:8b

log "Modelo opcional Apache-2.0 (gpt-oss:20b). Ctrl-C para pular em 5s..."
sleep 5 || true
docker exec "$OLLAMA_CONTAINER" ollama pull gpt-oss:20b || warn "gpt-oss:20b pulado."

# --- Aliases lógicos (usados nas rotas do gateway) -------------------------
# Usa `ollama create` a partir dos Modelfiles para aplicar temperature/num_ctx
# do catálogo (o `ollama cp` copiaria o base sem esses parâmetros).
log "Criando aliases lógicos (cutcast-cuts, cutcast-vision) com parâmetros..."
docker exec "$OLLAMA_CONTAINER" ollama create cutcast-cuts   -f /modelfiles/cutcast-cuts.Modelfile   || warn "falha ao criar cutcast-cuts"
docker exec "$OLLAMA_CONTAINER" ollama create cutcast-vision -f /modelfiles/cutcast-vision.Modelfile || warn "falha ao criar cutcast-vision"

# --- Whisper: dispara o download do modelo ---------------------------------
log "Disparando download do modelo whisper (large-v3)..."
if docker ps --format '{{.Names}}' | grep -q "^localai-whisper$"; then
  # Uma requisição vazia força o server a baixar/carregar o modelo.
  docker exec localai-whisper sh -c 'curl -fsS http://localhost:8000/ >/dev/null 2>&1' || \
    warn "whisper ainda inicializando; o modelo baixa no primeiro uso."
else
  warn "container whisper não está rodando; suba com 'make up'."
fi

# --- LocalAI: modelo de imagem (preload OPCIONAL, não fatal) ---------------
# A definição real está em config/localai/flux-dev.yaml (montado em /models).
# Este passo apenas AQUECE o download dos pesos com uma geração trivial.
# Pulável se você não for usar imagem agora (perfil image inativo).
IMAGES_PORT="${IMAGES_PORT:-18002}"
if docker ps --format '{{.Names}}' | grep -q "^${IMAGES_CONTAINER}$"; then
  log "Aquecendo o modelo de imagem (flux-dev) via POST trivial..."
  curl -fsS -X POST "http://localhost:${IMAGES_PORT}/v1/images/generations" \
    -H "Content-Type: application/json" \
    -d '{"model":"flux-dev","prompt":"warmup","size":"256x256","n":1}' >/dev/null 2>&1 \
    && log "modelo de imagem aquecido." \
    || warn "aquecimento de imagem falhou (pulável se não usar imagem agora; verifique HUGGING_FACE_HUB_TOKEN)."
else
  warn "container images não está rodando (perfil image inativo); pule ou rode 'make up-all'."
fi

log "Pronto. Rode 'make smoke' para validar as rotas."
