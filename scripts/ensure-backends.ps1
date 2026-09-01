# scripts/ensure-backends.ps1
# Aguarda o backend diffusers OCI no container LocalAI (cuda12-diffusers).
# Uso: powershell -ExecutionPolicy Bypass -File scripts/ensure-backends.ps1

$ImagesContainer = if ($env:IMAGES_CONTAINER) { $env:IMAGES_CONTAINER } else { 'localai-images' }
$BackendName = if ($env:LOCALAI_EXTERNAL_BACKENDS) { $env:LOCALAI_EXTERNAL_BACKENDS } else { 'cuda12-diffusers' }
$WaitSec = if ($env:ENSURE_BACKENDS_WAIT_SEC) { [int]$env:ENSURE_BACKENDS_WAIT_SEC } else { 300 }

function Log  ($m) { Write-Host "[backends] $m" -ForegroundColor Blue }
function Warn ($m) { Write-Host "[warn] $m" -ForegroundColor Yellow }

$running = (docker ps --format '{{.Names}}') -contains $ImagesContainer
if (-not $running) {
  Warn "container $ImagesContainer não está rodando (perfil image inativo?)."
  exit 1
}

Log "Aguardando backend $BackendName em /backends (até ${WaitSec}s)..."
$elapsed = 0
while ($elapsed -lt $WaitSec) {
  docker exec $ImagesContainer test -d "/backends/$BackendName" 2>$null
  if ($LASTEXITCODE -eq 0) {
    Log "backend $BackendName presente em /backends."
    exit 0
  }
  Start-Sleep -Seconds 5
  $elapsed += 5
}

Warn "backend $BackendName não instalado após ${WaitSec}s."
Warn "Verifique LOCALAI_EXTERNAL_BACKENDS=$BackendName no compose e os logs:"
Warn "  docker compose logs images"
Warn "Instalação manual (último recurso):"
Warn "  docker exec $ImagesContainer /local-ai backends install $BackendName"
exit 1
