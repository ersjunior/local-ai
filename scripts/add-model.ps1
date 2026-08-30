# scripts/add-model.ps1
# Gêmeo PowerShell de add-model.sh. Cria config/models/<nome>.yaml a partir de
# um template e imprime o bloco `model_list` para colar em gateway/config.yaml.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/add-model.ps1 <logical_name> <backend> <model_id> [alias]
#   ex.: ... add-model.ps1 chat-mistral ollama mistral-small:24b
#
# Backends válidos: ollama | whisper | localai | vllm
param(
  [Parameter(Mandatory=$true)][string]$Logical,
  [Parameter(Mandatory=$true)][string]$Backend,
  [Parameter(Mandatory=$true)][string]$ModelId,
  [string]$Alias = ''
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Out  = Join-Path $Root "config/models/$Logical.yaml"

if (Test-Path $Out) {
  Write-Host "[X] Já existe: $Out" -ForegroundColor Red
  exit 1
}

# --- Cria o arquivo de catálogo -------------------------------------------
@"
# CATÁLOGO — fonte de verdade / documentação de um modelo.
# Ao adicionar este arquivo, adicione TAMBÉM a rota em
# config/gateway/config.yaml (model_list). Bloco pronto impresso abaixo.

logical_name: $Logical
backend: $Backend
model_id: $ModelId
alias: "$Alias"
params:
  temperature: 0.7
  num_ctx: 8192
vram_estimate: "PREENCHER"
license: "PREENCHER (garanta uso comercial por padrão)"
notes: >
  PREENCHER.
enabled: true
"@ | Set-Content -Path $Out -Encoding utf8

Write-Host "[OK] Criado: $Out" -ForegroundColor Green
Write-Host ''

# --- Monta o bloco model_list conforme o backend --------------------------
$routeModel = if ($Alias) { $Alias } else { $ModelId }

Write-Host 'Cole este bloco em config/gateway/config.yaml (dentro de model_list):'
Write-Host '-----------------------------------------------------------------------'
switch ($Backend) {
  'ollama' {
@"
  - model_name: $Logical
    litellm_params:
      model: ollama_chat/$routeModel
      api_base: http://ollama:11434
    model_info:
      mode: chat
      metadata:
        catalog: $Logical.yaml
"@
  }
  'whisper' {
@"
  - model_name: $Logical
    litellm_params:
      model: openai/$ModelId
      api_base: http://whisper:8000/v1
      api_key: "dummy"
    model_info:
      mode: audio_transcription
      metadata:
        catalog: $Logical.yaml
"@
  }
  'localai' {
@"
  - model_name: $Logical
    litellm_params:
      model: openai/$ModelId
      api_base: http://images:8080/v1
      api_key: "dummy"
    model_info:
      mode: image_generation
      metadata:
        catalog: $Logical.yaml
"@
  }
  'vllm' {
@"
  - model_name: $Logical
    litellm_params:
      model: openai/$ModelId
      api_base: http://vllm:8000/v1
      api_key: "dummy"
    model_info:
      mode: chat
      metadata:
        catalog: $Logical.yaml
"@
  }
  default { Write-Host "backend desconhecido '$Backend' — edite a rota manualmente." -ForegroundColor Yellow }
}
Write-Host '-----------------------------------------------------------------------'
Write-Host 'Depois: task pull (se necessário) && task smoke'
