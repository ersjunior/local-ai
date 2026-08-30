# Arquitetura

## Visão geral

Todos os projetos consumidores apontam para **um único gateway** (LiteLLM).
Eles só precisam saber `OPENAI_BASE_URL` + uma virtual key, e escolhem o modelo
por um **nome lógico** (`chat-cuts`, `vision-default`, `whisper`, `image-thumbs`).

```
                        ┌───────────────────────────────────────────┐
   Projeto A ─┐         │            Host (Ryzen 9 5900X)            │
   Projeto B ─┼──HTTP──►│  Gateway LiteLLM  :4000/v1                 │
   Projeto C ─┘         │  - roteia por nome lógico                  │
   (só sabem            │  - virtual keys (rpm/tpm/parallel)         │
    BASE_URL+key)       │  - logging de uso                         │
                        │        │            │           │         │
                        │        ▼            ▼           ▼         │
                        │  ┌─────────┐  ┌──────────┐ ┌──────────┐   │
                        │  │ Ollama  │  │ Whisper  │ │ LocalAI  │   │
                        │  │ chat +  │  │ áudio    │ │ imagem   │   │
                        │  │ visão   │  │ :18001   │ │ :18002   │   │
                        │  │ :11434  │  └──────────┘ └──────────┘   │
                        │  └─────────┘                              │
                        │       └──────── RTX 4090 (24 GB VRAM) ────┘
                        │            (single-GPU, serializado)        │
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
