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

# Rotas diretas (fallback caso o gateway não proxyar áudio/imagem).
WHISPER_DIRECT="${WHISPER_DIRECT:-http://localhost:18001}"
IMAGES_DIRECT="${IMAGES_DIRECT:-http://localhost:18002}"
# API key do whisper (server exige Bearer quando definida). Usada na rota direta.
WHISPER_API_KEY="${WHISPER_API_KEY:-}"

pass() { printf '\033[1;32m✅ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m❌ %s\033[0m\n' "$*"; }

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- 1) Chat (JSON) --------------------------------------------------------
echo "== chat-cuts (chat/completions, JSON) =="
if curl -fsS -X POST "$BASE/chat/completions" -H "$AUTH" -H "$JSON" -d '{
  "model": "chat-cuts",
  "messages": [{"role":"user","content":"Responda apenas com JSON: {\"ok\": true}"}],
  "response_format": {"type":"json_object"}
}' >/dev/null 2>&1; then pass "chat-cuts"; else fail "chat-cuts"; fi

# --- 2) Visão (image_url) --------------------------------------------------
echo "== vision-default (image_url) =="
# 1x1 PNG transparente em base64.
PNG="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
if curl -fsS -X POST "$BASE/chat/completions" -H "$AUTH" -H "$JSON" -d "{
  \"model\": \"vision-default\",
  \"messages\": [{\"role\":\"user\",\"content\":[
     {\"type\":\"text\",\"text\":\"O que você vê?\"},
     {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$PNG\"}}
  ]}]
}" >/dev/null 2>&1; then pass "vision-default"; else fail "vision-default"; fi

# --- 3) Transcrição (gera um wav curto com ffmpeg) -------------------------
echo "== whisper (audio/transcriptions) =="
WAV="$TMPDIR/tone.wav"
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -ar 16000 -ac 1 "$WAV" -y >/dev/null 2>&1
else
  fail "ffmpeg ausente — pulando geração de wav"; WAV=""
fi
if [ -n "$WAV" ]; then
  if curl -fsS -X POST "$BASE/audio/transcriptions" -H "$AUTH" \
       -F "model=whisper" -F "file=@$WAV" -F "response_format=verbose_json" >/dev/null 2>&1; then
    pass "whisper (via gateway)"
  elif curl -fsS -X POST "$WHISPER_DIRECT/v1/audio/transcriptions" \
       -H "Authorization: Bearer $WHISPER_API_KEY" \
       -F "model=large-v3" -F "file=@$WAV" -F "response_format=verbose_json" >/dev/null 2>&1; then
    pass "whisper (rota direta $WHISPER_DIRECT)"
  else
    fail "whisper"
  fi
fi

# --- 4) Imagem (prompt simples) --------------------------------------------
echo "== image-thumbs (images/generations) =="
if curl -fsS -X POST "$BASE/images/generations" -H "$AUTH" -H "$JSON" -d '{
  "model": "image-thumbs",
  "prompt": "a small red circle on white background",
  "size": "512x512",
  "n": 1
}' >/dev/null 2>&1; then
  pass "image-thumbs (via gateway)"
elif curl -fsS -X POST "$IMAGES_DIRECT/v1/images/generations" -H "$JSON" -d '{
  "model": "flux-dev",
  "prompt": "a small red circle on white background",
  "size": "512x512",
  "n": 1
}' >/dev/null 2>&1; then
  pass "image-thumbs (rota direta $IMAGES_DIRECT)"
else
  fail "image-thumbs"
fi

echo "Smoke-test concluído."
