# Arquitetura

## Visão geral

Todos os projetos consumidores apontam para **um único gateway** (LiteLLM).
Eles só precisam saber `OPENAI_BASE_URL` + uma virtual key, e escolhem o modelo
por um **nome lógico** (`chat-cuts`, `vision-default`, `whisper`, `image-thumbs`).

Apps externas podem ainda registar **modelos dinâmicos** via **Model Registry**
(`:4010/registry/v1`), sem alterar os modelos base.

```
                        ┌───────────────────────────────────────────┐
   Projeto A ─┐         │            Host (Ryzen 9 5900X)            │
   Projeto B ─┼──HTTP──►│  Gateway LiteLLM  :4000/v1                 │
   Projeto C ─┘         │  Postgres :5432 (litellm + registry)       │
   (BASE_URL+key)       │        │            │           │         │
                        │        ▼            ▼           ▼         │
                        │  ┌─────────┐  ┌──────────┐ ┌──────────┐   │
                        │  │ Ollama  │  │ Whisper  │ │ LocalAI  │   │
                        │  │ chat +  │  │ áudio    │ │ imagem   │   │
                        │  │ visão   │  │ :18001   │ │ :18002   │   │
                        │  └─────────┘  └──────────┘ └──────────┘   │
                        │       └──────── RTX 4090 (24 GB VRAM) ────┘
                        │  Registry :4010 + Worker + Redis (perfil core) │
                        │  vLLM :18000 (perfil perf, opcional)        │
                        └───────────────────────────────────────────┘
```

## Orçamento de VRAM (single RTX 4090, 24 GB)

Regra de ouro: **nunca deixar LLM e modelo de imagem quentes ao mesmo tempo.**

| Modelo                | VRAM aprox. | Observação                          |
|-----------------------|-------------|-------------------------------------|
| Qwen3-32B (Q4)        | ~20 GB      | ocupa quase toda a GPU sozinho      |
| gpt-oss-20b (Q4)      | ~13 GB      | folgado                             |
| Qwen3-VL-7B           | ~7 GB       | folgado                             |
| whisper large-v3      | ~4–5 GB     | pode co-residir com VLM pequeno     |
| imagem (Diffusers)    | ~12–18 GB   | carregar **sob demanda**            |

Os 128 GB de RAM funcionam como **cache quente de pesos**: mesmo descarregando
da VRAM, os pesos permanecem no cache de disco/página e recarregam rápido.

## Política de load/unload

1. **Ollama** com `OLLAMA_KEEP_ALIVE=5m` e `OLLAMA_MAX_LOADED_MODELS=1`:
   descarrega o LLM da VRAM após inatividade, liberando espaço para imagem.
2. **Imagem (LocalAI)** carrega **sob demanda** e é liberada depois.
3. **`max_parallel_requests` baixo** por virtual key no gateway → as etapas
   pesadas (LLM vs imagem) se intercalam no tempo em vez de competir por VRAM.

Assim, um pipeline típico (transcrever → gerar cortes com LLM → thumbnail com
imagem) roda em série no mesmo 4090 sem OOM.

## Broker de GPU

### Caminho simples (recomendado — já implementado por configuração)

- `OLLAMA_KEEP_ALIVE` curto (descarrega antes da imagem).
- Imagem só sob demanda.
- `max_parallel_requests` baixo no gateway (guard global).

Isso basta para a maioria dos pipelines single-GPU: as cargas se serializam
naturalmente no tempo.

### Caminho avançado (opcional — TODO/skeleton)

Um pequeno serviço **`gpu-broker`** que o gateway consulta antes de despachar
requisições pesadas. Ideia de interface (não implementar agora):

```
POST /acquire  { "kind": "llm" | "image", "estimate_gb": 18 }
   -> 200 { "token": "...", "granted": true }   (bloqueia até haver VRAM)
POST /release  { "token": "..." }
```

Implementação sugerida: um semáforo/lock em Redis (`SETNX gpu:lock`) com TTL,
onde `kind=llm` e `kind=image` compartilham o mesmo lock (exclusão mútua) e
`estimate_gb` decide quantos slots simultâneos são permitidos. O gateway
chamaria `/acquire` num pre-call hook e `/release` no post-call.

> Status: **não implementado**. O caminho simples cobre o cenário single-4090.

## vLLM (perfil perf)

vLLM oferece alta vazão e **guided JSON** (saída estruturada garantida). Porém
reserva ~90% da VRAM e **não co-reside** com imagem no mesmo 4090. Use o perfil
`perf` isoladamente (GPU dedicada, ou quando rodar só texto).

## Banco de dados (PostgreSQL compartilhado)

```
   gateway (LiteLLM) ──► postgres:5432 ──► database `litellm` (role litellm)
   registry API      ──► postgres:5432 ──► database `registry` (role registry)
                                       └─► database `appN`    (role appN)   [futuro]
```

O LiteLLM exige um banco para persistir **virtual keys**, orçamentos e logs
(`store_model_in_db: true` + `database_url`). Sem ele, o gateway entra em loop
de reinício.

Decisão de arquitetura: **um servidor Postgres compartilhado**, com **um
database + um role por aplicação** (não um container por app). Isso escala e
mantém isolamento de schema:

- Serviço `postgres` (perfil `core`, `postgres:16`), rede `localai_net`.
- Superusuário `POSTGRES_USER`; o gateway conecta com o role/db dedicados
  `litellm` (host interno `postgres`, porta 5432).
- Init idempotente em `config/postgres/init/01-init.sh` cria role+db checando
  `pg_roles`/`pg_database` (roda só na 1ª criação do volume `localai_pg`).
- Volume **nomeado** (`localai_pg`) — nunca bind-mount (evita corrupção no
  disco Windows). Porta 5432 exposta no host (DBeaver/pgAdmin), atrás de senha
  forte.

Adicionar app nova = novo role + novo database no mesmo servidor (template no
fim do script de init, ou via `psql`). Ver README (seção Banco de dados).

## Model Registry (modelos dinâmicos multi-app)

Serviço **genérico** para apps externas registarem modelos sem alterar o
catálogo base do operador.

```
App externa ──Bearer sk-...──► Registry API (:4010/registry/v1)
                                    │
                                    ▼
                              Postgres (registry.dynamic_models)
                                    │
                              Registry Worker ──► Ollama pull (API)
                                    │              LiteLLM POST /model/new
                                    ▼
App externa ──Bearer sk-...──► Gateway (:4000/v1) ──► backends
```

Componentes (perfil `core`):

| Serviço | Função |
|---------|--------|
| `registry` | API FastAPI (`/registry/v1`) |
| `registry-worker` | Jobs assíncronos (pull, register, delete) |
| `redis` | Coordenação (health; idempotency futura) |

**Multi-tenant:** cada virtual key mapeia para `owner_app_id` (via
`metadata.app_id` na key). Modelos base (`is_base=true`) são read-only;
modelos dinâmicos usam prefixo `dyn-{app}-{alias}`.

**Integração LiteLLM:** `store_model_in_db: true` + `POST /model/new` e
`POST /model/delete` — hot reload, sem reinício do stack.

**Fontes v1:** `ollama` (pull nativo), `huggingface` (via `ollama pull hf.co/...`,
limitado). Ver [REGISTRY.md](REGISTRY.md).
