# Troubleshooting — geração de imagem (LocalAI / FLUX)

Sintomas comuns ao usar `image-thumbs` (flux-dev) no stack local-ai.

## Pré-requisitos

1. Perfil **image** ativo: `make up-all` ou `docker compose --profile core --profile image up -d`
2. `HUGGING_FACE_HUB_TOKEN` no `.env` (repo FLUX.1-dev é **gated**)
3. Termos aceites em [huggingface.co/black-forest-labs/FLUX.1-dev](https://huggingface.co/black-forest-labs/FLUX.1-dev)
4. Backend OCI **cuda12-diffusers** instalado em `/backends` (automático via `LOCALAI_EXTERNAL_BACKENDS`)

Ordem recomendada na 1ª subida:

```bash
make build          # 1ª vez: imagem do registry (perfil core)
make up-all         # core + image
make ensure-backends  # aguarda cuda12-diffusers (opcional; pull também verifica)
make pull           # baixa pesos Ollama + warmup FLUX (pode demorar)
make smoke
```

---

## Tabela de sintomas

| Sintoma | Causa provável | Correção |
|---------|----------------|----------|
| `Backend not found: backend="diffusers"` | Backend OCI não instalado em `/backends` | `LOCALAI_EXTERNAL_BACKENDS=cuda12-diffusers` no compose + volume `localai_backends:/backends`. Aguarde `start_period` (300s) ou `make ensure-backends` |
| HF **401/403** ao baixar FLUX | Token em falta ou termos não aceites | Defina `HUGGING_FACE_HUB_TOKEN` e aceite a licença no HuggingFace |
| Gateway **503** em `image-thumbs` | Cooldown LiteLLM após falhas repetidas no LocalAI | Corrija backend/HF; `docker compose restart images gateway` |
| **CUDA OOM** ao carregar FLUX | `f16: false` carrega em float32 (estoura 24GB) | Confirme `options: [torch_dtype:bf16]` em `config/localai/flux-dev.yaml` |
| FLUX lento / timeout no gateway | Cold start 5–15 min; router timeout curto | `router_settings.timeout: 1200` no gateway; descarregue Ollama antes de gerar imagem |
| `localai-gateway` **unhealthy** | Arranque lento (Postgres) ou healthcheck prematuro | `/health/liveliness` não exige auth (401 em `/health` é normal). Aguarde ou aumente `start_period` |
| Registry **401** | Master key em vez de virtual key | Use `sk-...` (virtual key) em `Authorization: Bearer` |
| Registry não responde em `:4010` | Perfil core sem build do registry | `make build` antes de `make up` |
| Registry DB error | Volume Postgres antigo sem DB `registry` | [REGISTRY.md#banco-de-dados](REGISTRY.md#banco-de-dados) |

---

## Verificações rápidas

```bash
# Backend diffusers presente?
docker exec localai-images ls /backends

# Modelos LocalAI
curl http://localhost:18002/v1/models

# Geração directa (sem gateway)
curl -X POST http://localhost:18002/v1/images/generations \
  -H "Content-Type: application/json" \
  -d '{"model":"flux-dev","prompt":"circulo vermelho","size":"512x512","n":1}'

# Via gateway
curl -X POST http://localhost:4000/v1/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"image-thumbs","prompt":"circulo vermelho","size":"512x512","n":1}'

# Registry (perfil core)
curl http://localhost:4010/registry/v1/health
```

---

## VRAM (single RTX 4090)

Não rode **chat/visão (Ollama)** e **imagem (FLUX)** ao mesmo tempo. Antes de `image-thumbs`:

```bash
docker exec localai-ollama ollama ps          # ver modelos carregados
docker exec localai-ollama ollama stop <nome> # descarregar se necessário
```

Ver também [adding-a-model.md](adding-a-model.md).

---

## Instalação manual do backend (último recurso)

Se `LOCALAI_EXTERNAL_BACKENDS` falhar:

```bash
docker exec localai-images /local-ai backends install cuda12-diffusers
```

O volume `localai_backends` persiste a instalação para recreates futuros.
