# scripts/pull-models.ps1
# Gêmeo PowerShell de pull-models.sh (Windows nativo, sem WSL).
# Baixa os pesos e cria os aliases lógicos do Ollama a partir dos Modelfiles.
# Uso: powershell -ExecutionPolicy Bypass -File scripts/pull-models.ps1

$ErrorActionPreference = 'Continue'

$OllamaContainer = if ($env:OLLAMA_CONTAINER) { $env:OLLAMA_CONTAINER } else { 'localai-ollama' }
$ImagesContainer = if ($env:IMAGES_CONTAINER) { $env:IMAGES_CONTAINER } else { 'localai-images' }

function Log  ($m) { Write-Host "[pull] $m" -ForegroundColor Blue }
function Warn ($m) { Write-Host "[warn] $m" -ForegroundColor Yellow }

# --- Ollama: LLMs + VLM ----------------------------------------------------
Log 'Baixando modelos do Ollama (isso pode demorar)...'
docker exec $OllamaContainer ollama pull qwen3:32b
docker exec $OllamaContainer ollama pull qwen3-vl:7b

Log 'Modelo opcional Apache-2.0 (gpt-oss:20b). Ctrl-C para pular em 5s...'
Start-Sleep -Seconds 5
docker exec $OllamaContainer ollama pull gpt-oss:20b
if ($LASTEXITCODE -ne 0) { Warn 'gpt-oss:20b pulado.' }

# --- Aliases lógicos (usam os Modelfiles montados em /modelfiles) ----------
Log 'Criando aliases lógicos (cutcast-cuts, cutcast-vision) com parâmetros...'
docker exec $OllamaContainer ollama create cutcast-cuts   -f /modelfiles/cutcast-cuts.Modelfile
if ($LASTEXITCODE -ne 0) { Warn 'falha ao criar cutcast-cuts' }
docker exec $OllamaContainer ollama create cutcast-vision -f /modelfiles/cutcast-vision.Modelfile
if ($LASTEXITCODE -ne 0) { Warn 'falha ao criar cutcast-vision' }

# --- Whisper: dispara o download do modelo ---------------------------------
Log 'Disparando download do modelo whisper (large-v3)...'
$whisperRunning = (docker ps --format '{{.Names}}') -contains 'localai-whisper'
if ($whisperRunning) {
  docker exec localai-whisper sh -c 'curl -fsS http://localhost:8000/ >/dev/null 2>&1'
  if ($LASTEXITCODE -ne 0) { Warn 'whisper ainda inicializando; o modelo baixa no primeiro uso.' }
} else {
  Warn "container whisper não está rodando; suba com 'task up' / 'make up'."
}

# --- LocalAI: modelo de imagem (preload OPCIONAL, não fatal) ---------------
$ImagesPort = if ($env:IMAGES_PORT) { $env:IMAGES_PORT } else { '18002' }
$ImageWarmupTimeout = if ($env:IMAGE_WARMUP_TIMEOUT) { $env:IMAGE_WARMUP_TIMEOUT } else { '600' }
$imagesRunning = (docker ps --format '{{.Names}}') -contains $ImagesContainer
if ($imagesRunning) {
  $ensureScript = Join-Path $PSScriptRoot 'ensure-backends.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $ensureScript
  if ($LASTEXITCODE -ne 0) {
    Warn 'backend cuda12-diffusers não instalado — aguarde o arranque do LocalAI ou defina LOCALAI_EXTERNAL_BACKENDS.'
  } else {
    Log "Aquecendo o modelo de imagem (flux-dev) via POST trivial (timeout ${ImageWarmupTimeout}s)..."
    $tmpOut = Join-Path $env:TEMP ("localai-warmup-" + [guid]::NewGuid().ToString('N'))
    $httpCode = & curl.exe --max-time $ImageWarmupTimeout -sS -o $tmpOut -w '%{http_code}' `
      -X POST "http://localhost:$ImagesPort/v1/images/generations" `
      -H 'Content-Type: application/json' `
      -d '{"model":"flux-dev","prompt":"warmup","size":"256x256","n":1}' 2>$null
    Remove-Item -Force $tmpOut -ErrorAction SilentlyContinue
    if ($httpCode -eq '200' -or $httpCode -eq '201') {
      Log 'modelo de imagem aquecido.'
    } elseif ($httpCode -eq '401' -or $httpCode -eq '403') {
      Warn "aquecimento falhou (HTTP $httpCode): token HF inválido ou termos FLUX.1-dev não aceites no HuggingFace."
      Warn 'Defina HUGGING_FACE_HUB_TOKEN no .env e aceite https://huggingface.co/black-forest-labs/FLUX.1-dev'
    } else {
      Warn "aquecimento de imagem falhou (HTTP $httpCode). Verifique logs: docker compose logs images"
    }
  }
} else {
  Warn "container images não está rodando (perfil image inativo); pule ou rode 'task up-all' / 'make up-all'."
}

Log "Pronto. Rode 'task smoke' / 'make smoke' para validar as rotas."
