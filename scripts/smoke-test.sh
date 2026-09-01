#!/usr/bin/env bash
# scripts/smoke-test.sh
# Testa todas as rotas via GATEWAY. Marca ✅/❌ por rota.
# Uso:
#   GATEWAY=http://localhost:4000 LITELLM_MASTER_KEY=sk-... bash scripts/smoke-test.sh
set -uo pipefail

GATEWAY="${GATEWAY:-http://localhost:4000}"
KEY="${LITELLM_MASTER_KEY:-sk-master-change-me}"
BASE="$GATEWAY/v1"
AUTH="Authorization: Bearer $KEY"
JSON="Content-Type: application/json"

# Timeouts (cold start Ollama 32B pode levar 2+ min; download FLUX é lento).
CURL_MAX_TIME_CHAT="${CURL_MAX_TIME_CHAT:-300}"
CURL_MAX_TIME_IMAGE="${CURL_MAX_TIME_IMAGE:-600}"

WHISPER_DIRECT="${WHISPER_DIRECT:-http://localhost:18001}"
IMAGES_DIRECT="${IMAGES_DIRECT:-http://localhost:18002}"
WHISPER_API_KEY="${WHISPER_API_KEY:-}"

pass() { printf '\033[1;32m✅ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m❌ %s\033[0m\n' "$*"; }
hint() { printf '\033[1;33m   → %s\033[0m\n' "$*"; }

curl_json() {
  local url="$1" body="$2" max_time="$3"
  curl --max-time "$max_time" -fsS -X POST "$url" -H "$AUTH" -H "$JSON" -d "$body" >/dev/null 2>&1
}

curl_json_direct() {
  local url="$1" body="$2" max_time="$3"
  curl --max-time "$max_time" -fsS -X POST "$url" -H "$JSON" -d "$body" >/dev/null 2>&1
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- 1) Chat (JSON) --------------------------------------------------------
echo "== chat-cuts (chat/completions, JSON) =="
if curl_json "$BASE/chat/completions" '{
  "model": "chat-cuts",
  "messages": [{"role":"user","content":"Responda apenas com JSON: {\"ok\": true}"}],
  "response_format": {"type":"json_object"}
}' "$CURL_MAX_TIME_CHAT"; then
  pass "chat-cuts"
else
  fail "chat-cuts (timeout ${CURL_MAX_TIME_CHAT}s — cold start Ollama pode demorar)"
fi

# --- 2) Visão (image_url) --------------------------------------------------
echo "== vision-default (image_url) =="
PNG="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
if curl --max-time "$CURL_MAX_TIME_CHAT" -fsS -X POST "$BASE/chat/completions" -H "$AUTH" -H "$JSON" -d "{
  \"model\": \"vision-default\",
  \"messages\": [{\"role\":\"user\",\"content\":[
     {\"type\":\"text\",\"text\":\"O que você vê?\"},
     {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$PNG\"}}
  ]}]
}" >/dev/null 2>&1; then
  pass "vision-default"
else
  fail "vision-default"
fi

# --- 3) Transcrição --------------------------------------------------------
echo "== whisper (audio/transcriptions) =="
WAV="$TMPDIR/tone.wav"
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -ar 16000 -ac 1 "$WAV" -y >/dev/null 2>&1
else
  fail "ffmpeg ausente — pulando geração de wav"; WAV=""
fi
if [ -n "$WAV" ]; then
  if curl --max-time 120 -fsS -X POST "$BASE/audio/transcriptions" -H "$AUTH" \
       -F "model=whisper" -F "file=@$WAV" -F "response_format=verbose_json" >/dev/null 2>&1; then
    pass "whisper (via gateway)"
  elif curl --max-time 120 -fsS -X POST "$WHISPER_DIRECT/v1/audio/transcriptions" \
       -H "Authorization: Bearer $WHISPER_API_KEY" \
       -F "model=large-v3" -F "file=@$WAV" -F "response_format=verbose_json" >/dev/null 2>&1; then
    pass "whisper (rota direta $WHISPER_DIRECT)"
  else
    fail "whisper"
  fi
fi

# --- 4) Imagem -------------------------------------------------------------
echo "== image-thumbs (images/generations) =="
IMG_BODY='{
  "model": "image-thumbs",
  "prompt": "a small red circle on white background",
  "size": "512x512",
  "n": 1
}'
if curl_json "$BASE/images/generations" "$IMG_BODY" "$CURL_MAX_TIME_IMAGE"; then
  pass "image-thumbs (via gateway)"
elif curl_json_direct "$IMAGES_DIRECT/v1/images/generations" '{
  "model": "flux-dev",
  "prompt": "a small red circle on white background",
  "size": "512x512",
  "n": 1
}' "$CURL_MAX_TIME_IMAGE"; then
  pass "image-thumbs (rota direta $IMAGES_DIRECT)"
else
  fail "image-thumbs"
  hint "Backend diffusers: confirme LOCALAI_EXTERNAL_BACKENDS=cuda12-diffusers e volume /backends"
  hint "HF token: HUGGING_FACE_HUB_TOKEN + termos aceites em huggingface.co/black-forest-labs/FLUX.1-dev"
  hint "Gateway 503 (cooldown): corrija LocalAI e reinicie localai-images + localai-gateway"
  hint "Ver docs/troubleshooting-images.md"
fi

echo "Smoke-test concluído."
