# Model Registry — API de modelos dinâmicos (multi-app)

API genérica de gestão de modelos dinâmicos para o stack **local-ai**.
Qualquer aplicação externa com uma **virtual key** pode registar, acompanhar e usar
modelos próprios via `/v1` — **sem alterar os modelos base** do compose.

## URL base

| Contexto | URL |
|----------|-----|
| Host (dev) | `http://localhost:4010/registry/v1` |
| Docker (mesma rede `localai_net`) | `http://registry:4010/registry/v1` |
| OpenAPI / Swagger | `http://localhost:4010/registry/docs` |
| OpenAPI JSON | `http://localhost:4010/registry/openapi.json` |

Inferência continua no gateway: `http://localhost:4000/v1` (modelos dinâmicos
usam o campo `litellm_route` / `model_name` devolvido pelo registry).

---

## Autenticação

Todos os endpoints (exceto `/health`) exigem:

```http
Authorization: Bearer sk-<virtual-key>
```

- A **master key** (`LITELLM_MASTER_KEY`) **não** é aceita no registry.
- O **tenant** (`owner_app_id`) é derivado da virtual key:
  1. `metadata.app_id` (preferido)
  2. `metadata.project`
  3. `team_id` da key
  4. fallback: `app-<hash-da-key>`

### Criar virtual key por app

```bash
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "models": ["chat-cuts","vision-default","whisper","image-thumbs"],
    "rpm_limit": 60,
    "tpm_limit": 200000,
    "max_parallel_requests": 2,
    "metadata": {
      "app_id": "cutcast",
      "project": "cutcast"
    }
  }'
```

Guarde o `"key": "sk-..."` — é o token para o registry **e** para `/v1`.

Para outra app (ex. `myapp`):

```json
"metadata": { "app_id": "myapp", "project": "myapp" }
```

---

## Modelos base vs dinâmicos

| Tipo | `is_base` | CRUD externo | Origem |
|------|-----------|--------------|--------|
| Base | `true` | **Read-only** (list/get) | `config/models/*.yaml` (catálogo) |
| Dinâmico | `false` | CRUD pelo **owner** | `POST /registry/v1/models` |

Modelos base (`chat-cuts`, `vision-default`, `whisper`, `image-thumbs`, …)
aparecem em `base_models` no `GET /models`. Tentativas de PATCH/DELETE retornam
**403** (`base_model_immutable`).

---

## Modelo de dados (campos estáveis)

```json
{
  "id": "uuid",
  "model_name": "dyn-cutcast-llama32-test",
  "litellm_route": "dyn-cutcast-llama32-test",
  "display_name": "Llama 3.2 test",
  "alias": "llama32-test",
  "source_type": "ollama",
  "source_uri": "ollama://llama3.2",
  "purpose": "chat",
  "status": "ready",
  "status_message": "registrado no LiteLLM",
  "progress": 100,
  "owner_app_id": "cutcast",
  "is_base": false,
  "managed_by": "tenant",
  "enabled": true,
  "external_ref": null,
  "metadata": {},
  "estimated_vram_mb": null,
  "size_bytes": null,
  "warm": false,
  "created_at": "...",
  "updated_at": "...",
  "ready_at": "..."
}
```

### Estados (`status`)

```
queued → downloading → loading → ready
                    ↘ failed
ready → disabling → disabled
ready → deleting → deleted
```

| Estado | Significado |
|--------|-------------|
| `queued` | Aceite; worker vai processar |
| `downloading` | Pull/download em curso |
| `loading` | Registo no LiteLLM |
| `ready` | Usável em `POST /v1/...` com `model=litellm_route` |
| `failed` | Erro em `status_message`; use `POST .../retry` |
| `disabling` / `disabled` | Desactivado (`enabled: false`) |
| `deleting` / `deleted` | Removido do LiteLLM |

---

## Endpoints

| Método | Path | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/registry/v1/health` | Não | Health check |
| GET | `/registry/v1/capabilities` | Sim | Fontes, purposes, limites |
| GET | `/registry/v1/models` | Sim | `base_models` + `owned_models` |
| POST | `/registry/v1/models` | Sim | Criar (202, assíncrono) |
| GET | `/registry/v1/models/{id}` | Sim | Detalhe (só own) |
| PATCH | `/registry/v1/models/{id}` | Sim | Update (só own) |
| DELETE | `/registry/v1/models/{id}` | Sim | Delete (202, assíncrono) |
| POST | `/registry/v1/models/{id}/retry` | Sim | Re-tentar se `failed` |
| POST | `/registry/v1/models/{id}/warm` | Sim | Marcar warm (UI futura) |

### Erros

```json
{ "detail": "mensagem legível", "code": "forbidden" }
```

| HTTP | `code` típico |
|------|----------------|
| 401 | `invalid_key`, `master_key_forbidden` |
| 403 | `forbidden`, `base_model_immutable` |
| 404 | `not_found` |
| 409 | `name_collision` |
| 429 | `quota_exceeded` |

### Idempotência

Envie `Idempotency-Key: <uuid>` no `POST /models`. Repetições com a mesma key
no mesmo tenant devolvem o registo existente.

---

## Fontes (v1)

### `source_type: ollama`

| `source_uri` | Exemplo |
|--------------|---------|
| Nome simples | `llama3.2`, `qwen3:8b` |
| Scheme | `ollama://llama3.2` |

Pipeline: `ollama pull` via API → registo LiteLLM `ollama_chat/<model>`.

### `source_type: huggingface`

| `source_uri` | Exemplo |
|--------------|---------|
| Shorthand | `Qwen/Qwen3-8B` |
| Scheme | `hf://Qwen/Qwen3-8B` |
| URL | `https://huggingface.co/Qwen/Qwen3-8B` |

**v1 (limitado):** HF para `chat`/`vision` tenta `ollama pull hf.co/{org}/{model}`.
`transcribe` e `image` via HF **falham** com mensagem explícita — use `ollama` ou
aguarde provisioner dedicado.

### `source_type: other`

Reservado; apenas domínios na allowlist (huggingface.co, hf.co, ollama.com).
`file://` e IPs privados são **bloqueados** (SSRF).

---

## Purposes → LiteLLM

| `purpose` | LiteLLM `mode` | Backend v1 |
|-----------|----------------|------------|
| `chat` | `chat` | Ollama |
| `vision` | `chat` (+ vision) | Ollama |
| `transcribe` | `audio_transcription` | Whisper (fixo) |
| `image` | `image_generation` | LocalAI (fixo) |

Rotas dinâmicas usam prefixo `dyn-{app_short}-{alias}` para evitar colisão com base.

---

## Integração LiteLLM (hot reload)

Quando `status` passa a `ready`, o worker chama:

- `POST http://gateway:4000/model/new` (master key)
- `POST http://gateway:4000/model/delete` no DELETE

Requer `store_model_in_db: true` e Postgres do gateway (já configurado).
**Sem reinício** do stack.

---

## Limites (configuráveis no `.env`)

| Variável | Default | Descrição |
|----------|---------|-----------|
| `REGISTRY_MAX_MODELS_PER_TENANT` | 10 | Modelos activos por app |
| `REGISTRY_MAX_CONCURRENT_DOWNLOADS` | 2 | Downloads globais simultâneos |
| `REGISTRY_OLLAMA_PULL_TIMEOUT_SEC` | 1800 | Timeout do pull Ollama |

---

## Banco de dados

- Servidor: Postgres partilhado (`postgres:5432`)
- Database: `registry` (role `registry`)
- Tabelas: `dynamic_models`, `audit_log`
- Init: `config/postgres/init/02-init-registry.sh` (só na 1ª criação do volume)

Se o volume Postgres **já existia** antes do registry, crie o DB manualmente:

```bash
docker exec -it localai-postgres psql -U localai -d postgres -c \
  "CREATE ROLE registry LOGIN PASSWORD 'sua-senha';"
docker exec -it localai-postgres psql -U localai -d postgres -c \
  "CREATE DATABASE registry OWNER registry;"
```

---

## Exemplos curl

Ver `scripts/registry-examples.sh`:

```bash
VIRTUAL_KEY=sk-... bash scripts/registry-examples.sh
```

### Criar modelo Ollama

```bash
curl -X POST http://localhost:4010/registry/v1/models \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "source_type": "ollama",
    "source_uri": "llama3.2",
    "purpose": "chat",
    "alias": "llama32",
    "display_name": "Llama 3.2"
  }'
```

### Chat com modelo dinâmico (quando `status=ready`)

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "dyn-cutcast-llama32",
    "messages": [{"role":"user","content":"Olá"}]
  }'
```

### Apagar (só owner)

```bash
curl -X DELETE http://localhost:4010/registry/v1/models/{id} \
  -H "Authorization: Bearer $VIRTUAL_KEY"
```

---

## Arquitectura

```
App externa ──Bearer sk-...──► Registry API (:4010/registry/v1)
                                    │
                                    ▼
                              Postgres (registry)
                                    │
                              Registry Worker ──► Ollama pull
                                    │              LiteLLM /model/new
                                    ▼
App externa ──Bearer sk-...──► Gateway (:4000/v1) ──► backends
```

Componentes (perfil `core`):

- `registry` — API FastAPI
- `registry-worker` — jobs assíncronos
- `redis` — coordenação (v1: health; idempotency futura)

---

## Testes

```bash
cd registry && pip install -r requirements.txt pytest && pytest tests/ -v
```

Ou: `make registry-test`

---

## Limitações conhecidas (v1)

1. **HuggingFace:** só via Ollama `hf.co/...`; sem download directo de GGUF/snapshot.
2. **HF `image`/`transcribe`:** não suportados — falham com mensagem clara.
3. **Warm:** marca flag; não executa pré-carga GPU real (TODO).
4. **Weights partilhados:** DELETE remove rota LiteLLM; pesos Ollama partilhados **não**
   são apagados se outro tenant usar o mesmo modelo.
5. **CORS:** `allow_origins=*` — ajustar em produção se browser aceder directamente.
6. **Init Postgres:** script `02-init-registry.sh` só corre na 1ª criação do volume.

---

## Notas para apps cliente (ex. CutCast — depois)

1. Nova aba “Novos modelos” → chama `POST /registry/v1/models`.
2. Proxy server-side ou CORS directo com `LOCAL_AI_API_KEY`.
3. Tabela com estados; botões Retry / Apagar / Usar como modelo activo.
4. `owner_app_id` vem da virtual key — **não** do `user_id` da app.
5. Campo opcional `external_ref` / `metadata` para correlacionar na app.
