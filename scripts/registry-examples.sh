#!/usr/bin/env bash
# scripts/registry-examples.sh — exemplos curl da API de registry
# Uso: VIRTUAL_KEY=sk-... bash scripts/registry-examples.sh
set -euo pipefail

REGISTRY="${REGISTRY:-http://localhost:4010}"
GATEWAY="${GATEWAY:-http://localhost:4000}"
KEY="${VIRTUAL_KEY:?defina VIRTUAL_KEY (virtual key de uma app)}"
AUTH="Authorization: Bearer $KEY"

echo "== GET /registry/v1/health =="
curl -s "$REGISTRY/registry/v1/health" | head -c 200; echo

echo "== GET /registry/v1/capabilities =="
curl -s -H "$AUTH" "$REGISTRY/registry/v1/capabilities" | head -c 400; echo

echo "== GET /registry/v1/models =="
curl -s -H "$AUTH" "$REGISTRY/registry/v1/models" | head -c 600; echo

echo "== POST /registry/v1/models (Ollama) =="
CREATE=$(curl -s -X POST "$REGISTRY/registry/v1/models" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -H "Idempotency-Key: smoke-ollama-$(date +%s)" \
  -d '{
    "source_type": "ollama",
    "source_uri": "llama3.2",
    "purpose": "chat",
    "display_name": "Llama 3.2 test",
    "alias": "llama32-test",
    "metadata": {"note": "registry smoke test"}
  }')
echo "$CREATE" | head -c 500; echo
MODEL_ID=$(echo "$CREATE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

if [ -n "${MODEL_ID:-}" ]; then
  echo "== GET /registry/v1/models/$MODEL_ID =="
  curl -s -H "$AUTH" "$REGISTRY/registry/v1/models/$MODEL_ID" | head -c 400; echo
fi

echo "== POST /v1/chat/completions (modelo dinâmico, quando ready) =="
echo "(aguarde status=ready no GET acima, depois use litellm_route como model)"
echo "curl -s $GATEWAY/v1/chat/completions -H \"$AUTH\" -H 'Content-Type: application/json' \\"
echo '  -d '"'"'{"model":"<litellm_route>","messages":[{"role":"user","content":"oi"}]}'"'"
