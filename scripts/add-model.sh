#!/usr/bin/env bash
# scripts/add-model.sh
# Scaffold de um novo modelo: cria config/models/<nome>.yaml a partir de um
# template e imprime o bloco `model_list` para colar em config/gateway/config.yaml.
#
# Uso:
#   bash scripts/add-model.sh <logical_name> <backend> <model_id> [alias]
#   ex.: bash scripts/add-model.sh chat-mistral ollama mistral-small:24b
#
# Backends válidos: ollama | whisper | localai | vllm
set -euo pipefail

LOGICAL="${1:-}"
BACKEND="${2:-}"
MODEL_ID="${3:-}"
ALIAS="${4:-}"

if [ -z "$LOGICAL" ] || [ -z "$BACKEND" ] || [ -z "$MODEL_ID" ]; then
  echo "Uso: bash scripts/add-model.sh <logical_name> <backend> <model_id> [alias]"
  echo "Backends: ollama | whisper | localai | vllm"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/config/models/${LOGICAL}.yaml"

if [ -e "$OUT" ]; then
  echo "❌ Já existe: $OUT"; exit 1
fi

# --- Cria o arquivo de catálogo -------------------------------------------
cat > "$OUT" <<EOF
# CATÁLOGO — fonte de verdade / documentação de um modelo.
# Ao adicionar este arquivo, adicione TAMBÉM a rota em
# config/gateway/config.yaml (model_list). Bloco pronto impresso abaixo.

logical_name: ${LOGICAL}
backend: ${BACKEND}
model_id: ${MODEL_ID}
alias: "${ALIAS}"
params:
  temperature: 0.7
  num_ctx: 8192
vram_estimate: "PREENCHER"
license: "PREENCHER (garanta uso comercial por padrão)"
notes: >
  PREENCHER.
enabled: true
EOF

echo "✅ Criado: $OUT"
echo ""

# --- Monta o bloco model_list conforme o backend --------------------------
ROUTE_MODEL="$MODEL_ID"
[ -n "$ALIAS" ] && ROUTE_MODEL="$ALIAS"

echo "Cole este bloco em config/gateway/config.yaml (dentro de model_list):"
echo "-----------------------------------------------------------------------"
case "$BACKEND" in
  ollama)
    cat <<EOF
  - model_name: ${LOGICAL}
    litellm_params:
      model: ollama_chat/${ROUTE_MODEL}
      api_base: http://ollama:11434
    model_info:
      mode: chat
      metadata:
        catalog: ${LOGICAL}.yaml
EOF
    ;;
  whisper)
    cat <<EOF
  - model_name: ${LOGICAL}
    litellm_params:
      model: openai/${MODEL_ID}
      api_base: http://whisper:8000/v1
      api_key: "dummy"
    model_info:
      mode: audio_transcription
      metadata:
        catalog: ${LOGICAL}.yaml
EOF
    ;;
  localai)
    cat <<EOF
  - model_name: ${LOGICAL}
    litellm_params:
      model: openai/${MODEL_ID}
      api_base: http://images:8080/v1
      api_key: "dummy"
    model_info:
      mode: image_generation
      metadata:
        catalog: ${LOGICAL}.yaml
EOF
    ;;
  vllm)
    cat <<EOF
  - model_name: ${LOGICAL}
    litellm_params:
      model: openai/${MODEL_ID}
      api_base: http://vllm:8000/v1
      api_key: "dummy"
    model_info:
      mode: chat
      metadata:
        catalog: ${LOGICAL}.yaml
EOF
    ;;
  *)
    echo "⚠️ backend desconhecido '$BACKEND' — edite a rota manualmente."
    ;;
esac
echo "-----------------------------------------------------------------------"
echo "Depois: make pull (se necessário) && make smoke"
