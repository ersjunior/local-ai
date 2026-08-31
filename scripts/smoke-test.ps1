# scripts/smoke-test.ps1
# Gêmeo PowerShell de smoke-test.sh. Testa todas as rotas via GATEWAY, com
# fallback para as rotas diretas (:18001 / :18002). Saída ✅/❌ por rota.
# Usa curl.exe (presente no Windows 10+). Gera o wav de teste num container
# se ffmpeg não estiver instalado no host.
#
# Uso:
#   $env:GATEWAY="http://localhost:4000"; $env:LITELLM_MASTER_KEY="sk-..."
#   powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1

$ErrorActionPreference = 'Continue'

$Gateway = if ($env:GATEWAY) { $env:GATEWAY } else { 'http://localhost:4000' }
$Key     = if ($env:LITELLM_MASTER_KEY) { $env:LITELLM_MASTER_KEY } else { 'sk-master-change-me' }
$Base    = "$Gateway/v1"
$Auth    = "Authorization: Bearer $Key"
$Json    = 'Content-Type: application/json'

$WhisperDirect = if ($env:WHISPER_DIRECT) { $env:WHISPER_DIRECT } else { 'http://localhost:18001' }
$ImagesDirect  = if ($env:IMAGES_DIRECT)  { $env:IMAGES_DIRECT }  else { 'http://localhost:18002' }
# API key do whisper (server exige Bearer quando definida). Usada na rota direta.
$WhisperKey    = if ($env:WHISPER_API_KEY) { $env:WHISPER_API_KEY } else { '' }

function Pass ($m) { Write-Host "[OK] $m"   -ForegroundColor Green }
function Fail ($m) { Write-Host "[X]  $m"   -ForegroundColor Red }

$Tmp = Join-Path $env:TEMP ("localai-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

# Helper: POST JSON de um arquivo; retorna $true se HTTP 2xx.
function Invoke-CurlJson ($url, $bodyFile) {
  curl.exe -fsS -X POST $url -H $Auth -H $Json --data "@$bodyFile" -o $null 2>$null
  return ($LASTEXITCODE -eq 0)
}

try {
  # --- 1) Chat (JSON) ------------------------------------------------------
  Write-Host '== chat-cuts (chat/completions, JSON) =='
  $chatFile = Join-Path $Tmp 'chat.json'
  '{"model":"chat-cuts","messages":[{"role":"user","content":"Responda apenas com JSON: {\"ok\": true}"}],"response_format":{"type":"json_object"}}' | Set-Content -Path $chatFile -Encoding ascii
  if (Invoke-CurlJson "$Base/chat/completions" $chatFile) { Pass 'chat-cuts' } else { Fail 'chat-cuts' }

  # --- 2) Visão (image_url) ------------------------------------------------
  Write-Host '== vision-default (image_url) =='
  $png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
  $visFile = Join-Path $Tmp 'vision.json'
  "{`"model`":`"vision-default`",`"messages`":[{`"role`":`"user`",`"content`":[{`"type`":`"text`",`"text`":`"O que voce ve?`"},{`"type`":`"image_url`",`"image_url`":{`"url`":`"data:image/png;base64,$png`"}}]}]}" | Set-Content -Path $visFile -Encoding ascii
  if (Invoke-CurlJson "$Base/chat/completions" $visFile) { Pass 'vision-default' } else { Fail 'vision-default' }

  # --- 3) Transcrição (gera um wav curto) ----------------------------------
  Write-Host '== whisper (audio/transcriptions) =='
  $wav = Join-Path $Tmp 'tone.wav'
  if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -ar 16000 -ac 1 $wav -y 2>$null | Out-Null
  } else {
    Write-Host '   ffmpeg ausente no host; gerando wav dentro de um container...'
    $tmpUnix = $Tmp -replace '\\', '/'
    docker run --rm -v "${tmpUnix}:/out" jrottenberg/ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -ar 16000 -ac 1 /out/tone.wav -y 2>$null | Out-Null
  }
  if (Test-Path $wav) {
    curl.exe -fsS -X POST "$Base/audio/transcriptions" -H $Auth -F 'model=whisper' -F "file=@$wav" -F 'response_format=verbose_json' -o $null 2>$null
    if ($LASTEXITCODE -eq 0) {
      Pass 'whisper (via gateway)'
    } else {
      curl.exe -fsS -X POST "$WhisperDirect/v1/audio/transcriptions" -H "Authorization: Bearer $WhisperKey" -F 'model=large-v3' -F "file=@$wav" -F 'response_format=verbose_json' -o $null 2>$null
      if ($LASTEXITCODE -eq 0) { Pass "whisper (rota direta $WhisperDirect)" } else { Fail 'whisper' }
    }
  } else {
    Fail 'whisper (não foi possível gerar o wav de teste)'
  }

  # --- 4) Imagem (prompt simples) ------------------------------------------
  Write-Host '== image-thumbs (images/generations) =='
  $imgFile = Join-Path $Tmp 'image.json'
  '{"model":"image-thumbs","prompt":"a small red circle on white background","size":"512x512","n":1}' | Set-Content -Path $imgFile -Encoding ascii
  if (Invoke-CurlJson "$Base/images/generations" $imgFile) {
    Pass 'image-thumbs (via gateway)'
  } else {
    $imgDirect = Join-Path $Tmp 'image-direct.json'
    '{"model":"qwen-image","prompt":"a small red circle on white background","size":"512x512","n":1}' | Set-Content -Path $imgDirect -Encoding ascii
    curl.exe -fsS -X POST "$ImagesDirect/v1/images/generations" -H $Json --data "@$imgDirect" -o $null 2>$null
    if ($LASTEXITCODE -eq 0) { Pass "image-thumbs (rota direta $ImagesDirect)" } else { Fail 'image-thumbs' }
  }

  Write-Host 'Smoke-test concluído.'
}
finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
