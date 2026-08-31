# local-ai

Plataforma de **inferência local em Docker** que expõe endpoints
**OpenAI-compatíveis** através de um **gateway único** (LiteLLM). Qualquer
projeto aponta apenas `OPENAI_BASE_URL` + uma chave e escolhe o modelo por um
**nome lógico** (`chat-cuts`, `vision-default`, `whisper`, `image-thumbs`).
Adicionar um modelo ao stack pode ser feito de **duas formas**:

1. **Operador** (manual): catálogo `config/models/` + rota no gateway — ver [adding-a-model.md](docs/adding-a-model.md).
2. **Apps externas** (dinâmico): API **Model Registry** em `/registry/v1` — cada app regista os seus modelos via virtual key, sem alterar os modelos base.

> Repositório **independente e genérico**. O CutCast aparece apenas como
> exemplo em `examples/` e `docs/`.

## Diagrama

```
   Projeto A ─┐
   Projeto B ─┼──HTTP──►  Gateway LiteLLM (:4000/v1)  ──►  Ollama   (chat+visão)
   Projeto C ─┘          roteia por nome lógico         ──►  Whisper  (áudio)
   (só sabem                virtual keys + limites       ──►  LocalAI  (imagem)
    BASE_URL+key)           logging de uso               ──►  vLLM     (perf, opcional)
                                                    RTX 4090 (24 GB, single-GPU)

   Apps externas ──►  Model Registry (:4010/registry/v1)
                      CRUD modelos dinâmicos (multi-tenant)
                      worker → ollama pull → LiteLLM /model/new (hot reload)
```

Detalhes em [docs/architecture.md](docs/architecture.md).

---

## Pré-requisitos por SO

O acesso à GPU NVIDIA dentro do Docker depende do SO:

| SO            | GPU NVIDIA no Docker                 | Recomendação                          |
|---------------|--------------------------------------|---------------------------------------|
| **Windows**   | Só via **WSL2** (CUDA-on-WSL)        | Docker Desktop + integração WSL2 ligada + driver NVIDIA recente. **Rode preferencialmente dentro do WSL2.** |
| **Linux**     | Nativo                               | Docker Engine + **NVIDIA Container Toolkit** |
| **macOS**     | **Sem** GPU NVIDIA                   | Só CPU / modelos leves. O alvo GPU é **Windows(WSL2)/Linux**. |

### Verificar a GPU no container

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

- **Windows**: rode esse comando **dentro do WSL2** (ou no Docker Desktop com o
  backend WSL2 ligado). Se aparecer sua RTX 4090, está tudo certo.
- **Linux**: rode direto no host (precisa do NVIDIA Container Toolkit).
- **macOS**: não se aplica (sem GPU NVIDIA).

### Instalar o runner (opcional)

Você pode usar `make`, `task` (go-task) **ou** os comandos `docker compose`
crus (baseline universal — sempre funcionam).

**go-task (`task`)** — cross-platform, um binário só:

| SO            | Instalação                                          |
|---------------|-----------------------------------------------------|
| Windows       | `winget install Task.Task` \| `choco install go-task` \| `scoop install task` |
| Linux/macOS   | `brew install go-task` \| script oficial em [taskfile.dev](https://taskfile.dev) |

**make**:

- **WSL2/Linux/macOS**: já vem (ou `sudo apt install make` / `xcode-select --install`).
- **Windows nativo** (se preferir make): `winget install GnuWin32.Make` \|
  `choco install make` \| `scoop install make`.

---

## Baseline universal (docker compose cru)

Funciona em **qualquer SO**, sem `make` nem `task`:

```bash
docker network create localai_net                                        # rede (uma vez)
docker compose --profile core up -d                                      # core: gateway+ollama+whisper
docker compose --profile core --profile image up -d                      # + imagem (LocalAI)
docker compose --profile perf up -d                                      # perfil perf (vLLM)
docker compose --profile core --profile image --profile perf config      # validar
docker compose logs -f                                                   # logs
docker compose --profile core --profile image --profile perf down        # derrubar tudo
```

Os passos de `pull`/`create-models`/`smoke` são scripts — use `.sh`
(WSL2/Linux/macOS) ou `.ps1` (Windows nativo), ou os alvos `make`/`task`.

---

## Quickstart por SO

Os passos são os mesmos em todos: **net → build → up → pull → create-models → smoke**.
Antes: `cp .env.example .env` (Windows PowerShell: `Copy-Item .env.example .env`)
e ajuste `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `POSTGRES_*`, `LITELLM_DB_*`,
`DATABASE_URL`, `REGISTRY_DB_*` e `REGISTRY_DATABASE_URL` (senhas devem bater).

> Na **primeira subida** com Postgres/registry: se o volume `local-ai_localai_pg`
> já existia antes destes serviços, crie o database `registry` manualmente — ver
> [REGISTRY.md](docs/REGISTRY.md#banco-de-dados).

### WSL2 (recomendado no Windows, com GPU)

```bash
cp .env.example .env
make build         # 1ª vez: constrói imagem do registry
make up            # ou: task up
make pull          # ou: task pull
make create-models # ou: task create-models
make smoke         # ou: task smoke
```

### Windows PowerShell (nativo)

```powershell
Copy-Item .env.example .env
# Opção A (runner):
task up ; task pull ; task create-models ; task smoke
# Opção B (docker compose cru + scripts .ps1):
docker network create localai_net
docker compose --profile core up -d
powershell -ExecutionPolicy Bypass -File scripts/pull-models.ps1
docker exec localai-ollama ollama create cutcast-cuts   -f /modelfiles/cutcast-cuts.Modelfile
docker exec localai-ollama ollama create cutcast-vision -f /modelfiles/cutcast-vision.Modelfile
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
```

> No Windows nativo a GPU só funciona com o **backend WSL2** do Docker Desktop
> ligado. Sem WSL2, os containers rodam em CPU.

### Linux / macOS

```bash
cp .env.example .env
make up            # ou: task up
make pull          # ou: task pull
make create-models # ou: task create-models
make smoke         # ou: task smoke
```

> macOS: sem GPU NVIDIA — use modelos leves / CPU.

---

## Tabela de equivalência `make` ↔ `task` ↔ `docker compose`

| Operação                | `make`             | `task`             | `docker compose` cru                                             |
|-------------------------|--------------------|--------------------|------------------------------------------------------------------|
| Criar rede              | `make net`         | `task net`         | `docker network create localai_net`                              |
| Subir core              | `make up`          | `task up`          | `docker compose --profile core up -d`                            |
| Build registry (1ª vez) | `make build`       | `task build`       | `docker compose --profile core build registry`                   |
| Subir core + imagem     | `make up-all`      | `task up-all`      | `docker compose --profile core --profile image up -d`            |
| Subir perf (vLLM)       | `make perf`        | `task perf`        | `docker compose --profile perf up -d`                            |
| Validar config          | `make config`      | `task config`      | `docker compose --profile core --profile image --profile perf config` |
| Logs                    | `make logs`        | `task logs`        | `docker compose logs -f`                                         |
| Derrubar                | `make down`        | `task down`        | `docker compose --profile core --profile image --profile perf down` |
| Baixar pesos            | `make pull`        | `task pull`        | `scripts/pull-models.sh` (WSL/Linux/mac) ou `scripts/pull-models.ps1` (Win) |
| Criar aliases           | `make create-models` | `task create-models` | `docker exec localai-ollama ollama create ... -f /modelfiles/...` |
| Smoke-test              | `make smoke`       | `task smoke`       | `scripts/smoke-test.sh` ou `scripts/smoke-test.ps1`              |
| Virtual key exemplo     | `make key`         | `task key`         | `curl -X POST .../key/generate ...`                              |
| Scaffold de modelo      | `make add-model`   | `task add-model -- <args>` | `scripts/add-model.sh` ou `scripts/add-model.ps1`        |
| Testes registry         | `make registry-test` | `task registry-test` | `cd registry && pytest tests/ -v`                          |
| Exemplos registry       | `make registry-examples` | `task registry-examples` | `VIRTUAL_KEY=sk-... scripts/registry-examples.sh`      |

O `task` escolhe automaticamente `.sh` (Linux/macOS/WSL2) ou `.ps1` (Windows
nativo) via `platforms:`.

### Perfis

| Perfil | Serviços |
|--------|----------|
| core   | postgres + redis + gateway + ollama + whisper + **registry** + **registry-worker** |
| image  | + LocalAI (geração de imagem) |
| perf   | vLLM (alta vazão / guided JSON) |

### Portas no host

| Serviço | Porta  | Rota                              |
|---------|--------|-----------------------------------|
| gateway  | 4000   | `/v1` (ponto de entrada único)    |
| ollama   | 11434  | interno por padrão (porta no host comentada no compose) |
| whisper  | 18001  | `/v1/audio/transcriptions`        |
| images   | 18002  | `/v1/images/generations`          |
| vllm     | 18000  | `/v1` (perfil perf)               |
| postgres | 5432   | banco (DBeaver/pgAdmin)           |
| registry | 4010   | `/registry/v1` (modelos dinâmicos) |

---

## Banco de dados (PostgreSQL compartilhado)

O gateway LiteLLM persiste virtual keys, orçamentos e logs de uso em Postgres.
O stack usa **um servidor Postgres compartilhado** (`postgres:16`, serviço
`postgres`, perfil `core`) com o padrão **um database + um role por aplicação**:

- O LiteLLM usa o database `litellm` (role `litellm`), criado idempotentemente
  pelo init `config/postgres/init/01-init.sh` na primeira subida.
- O **Model Registry** usa o database `registry` (role `registry`), criado pelo
  init `config/postgres/init/02-init-registry.sh`.
- Apps futuras do stack ganham **o seu próprio database** no mesmo servidor
  (sem 1 container por app), mantendo isolamento de schema.

Dados ficam em **volume nomeado** (`localai_pg`) — nunca bind-mount, para evitar
corrupção/permissão no disco Windows.

### Conectar via DBeaver / pgAdmin

| Campo    | Valor                              |
|----------|------------------------------------|
| Host     | `localhost`                        |
| Porta    | `5432` (`POSTGRES_PORT`)           |
| Usuário  | `POSTGRES_USER` (ex.: `localai`, superusuário) |
| Senha    | `POSTGRES_PASSWORD`                |
| Database | `postgres` (ou `litellm`, `registry`) |

### Adicionar uma nova aplicação (novo role + database)

Descomente/edite o **template** no fim de `config/postgres/init/01-init.sh`
(roda só ao criar o volume do zero), **ou** rode via `psql` num servidor já ativo:

```bash
docker exec -it localai-postgres psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE ROLE minhaapp LOGIN PASSWORD 'senha-forte';"
docker exec -it localai-postgres psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE DATABASE minhaapp OWNER minhaapp;"
```

> **Segurança**: a porta `5432` fica exposta no host. Use senhas fortes em
> `POSTGRES_PASSWORD` e `LITELLM_DB_PASSWORD`. O `.env` continua fora do git.

---

## Criar uma virtual key por projeto

```bash
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "models": ["chat-cuts","vision-default","whisper","image-thumbs"],
        "rpm_limit": 60,
        "tpm_limit": 200000,
        "max_parallel_requests": 2,
        "metadata": {"app_id": "meu-app", "project": "meu-app"}
      }'
```

Use `metadata.app_id` para identificar o tenant no **Model Registry** (cada app
só vê e gere os seus modelos dinâmicos). Atalhos: `make key` / `task key`.
A resposta traz `"key": "sk-..."`.

---

## Model Registry (modelos dinâmicos multi-app)

API de gestão para **apps externas** registarem modelos próprios sem alterar os
modelos base do stack (`chat-cuts`, `vision-default`, etc.).

| Item | Valor |
|------|-------|
| URL | `http://localhost:4010/registry/v1` |
| Swagger | `http://localhost:4010/registry/docs` |
| Auth | `Authorization: Bearer <virtual-key>` (master key **não** aceita) |
| Tenant | `metadata.app_id` (ou `project`) na virtual key |

### Fluxo resumido

1. App cria virtual key com `metadata.app_id`.
2. `POST /registry/v1/models` com `source_type` + `source_uri` + `purpose`.
3. Worker faz pull (Ollama/HF) e regista rota no LiteLLM (`POST /model/new`).
4. Quando `status=ready`, usar `litellm_route` em `POST /v1/chat/completions`.

```bash
# Criar modelo Ollama (assíncrono — acompanhar via GET /models/{id})
curl -X POST http://localhost:4010/registry/v1/models \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"source_type":"ollama","source_uri":"llama3.2","purpose":"chat","alias":"llama32"}'

# Inferir (quando ready)
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"dyn-meuapp-llama32","messages":[{"role":"user","content":"oi"}]}'
```

Regras: modelos **base** são read-only; cada app faz CRUD só nos **seus** modelos
(`dyn-{app}-{alias}`). Fontes v1: `ollama`, `huggingface` (limitado). Ver
[docs/REGISTRY.md](docs/REGISTRY.md) para estados, limites, segurança e troubleshooting.

```bash
make registry-test      # testes unitários (8 testes)
VIRTUAL_KEY=sk-... make registry-examples
```

---

## Modelos e licenças

| Nome lógico      | Backend | Modelo real          | Licença            | Comercial |
|------------------|---------|----------------------|--------------------|-----------|
| `chat-cuts`      | ollama  | qwen3:32b            | Qwen (restrições)  | Sim*      |
| `chat-gpt-oss`   | ollama  | gpt-oss:20b          | Apache-2.0         | Sim       |
| `vision-default` | ollama  | qwen3-vl:7b          | Qwen (restrições)  | Sim*      |
| `whisper`        | whisper | large-v3             | MIT                | Sim       |
| `image-thumbs`   | localai | **flux-schnell** (padrão) | Apache-2.0    | Sim       |
| `image-thumbs`   | localai | qwen-image (alternativa)  | Qwen-Image    | Sim*      |

\* verificar as restrições da licença Qwen. **Não-comerciais** (não usar por
padrão): FLUX.1-dev, FLUX.2-dev.

### Modelo de imagem (padrão: FLUX.1-schnell)

O padrão de `image-thumbs` é **flux-schnell** (12B, distilado, Apache-2.0):
cabe no 24 GB do RTX 4090 e é rápido (4 passos). Como o consumidor desenha o
texto do título por cima da imagem (bake via PIL), a renderização de texto do
modelo não é necessária — por isso o Qwen-Image (~20B, pesado no single-GPU)
fica só como **alternativa documentada** (`config/localai/qwen-image.yaml`).

> **FLUX.1-schnell é gated no HuggingFace.** Antes do primeiro `up` do perfil
> `image`: aceite os termos em
> [huggingface.co/black-forest-labs/FLUX.1-schnell](https://huggingface.co/black-forest-labs/FLUX.1-schnell)
> e defina `HUGGING_FACE_HUB_TOKEN` no `.env`. Para usar o Qwen-Image no lugar,
> troque uma linha na rota `image-thumbs` do gateway (ver
> [docs/adding-a-model.md](docs/adding-a-model.md)).

---

## Catálogo (adicionar um modelo)

O catálogo (`config/models/`) é a fonte de verdade e é **desacoplado** dos
projetos consumidores. Adicionar um modelo não exige mexer em nenhum consumidor.

```bash
# WSL/Linux/macOS
bash scripts/add-model.sh chat-mistral ollama mistral-small:24b
# Windows nativo
powershell -ExecutionPolicy Bypass -File scripts/add-model.ps1 chat-mistral ollama mistral-small:24b
# via task (qualquer SO)
task add-model -- chat-mistral ollama mistral-small:24b

# cole o bloco impresso em config/gateway/config.yaml, depois:
task pull ; docker compose restart gateway ; task smoke
```

Detalhes em [docs/adding-a-model.md](docs/adding-a-model.md).

---

## Troubleshooting

- **Erro `\r` / `command not found` ao rodar um `.sh` (no WSL/container)**:
  é CRLF do Windows. O `.gitattributes` já previne (força LF em `.sh`). Se você
  clonou **antes** dele existir: re-clone, ou rode
  `git add --renormalize .` (e commit), ou `dos2unix scripts/*.sh`.

- **GPU não aparece no Windows**: confirme o **backend WSL2** ligado no Docker
  Desktop (Settings → General → *Use WSL 2 based engine*) e o **driver NVIDIA**
  recente. Rode o `nvidia-smi` de teste **dentro do WSL2**. Sem WSL2, os
  containers usam CPU.

- **`localai_net` não existe** (`network localai_net declared as external...`):
  crie a rede com `docker network create localai_net` (ou `make net` / `task net`).

- **Áudio/imagem falham no smoke via gateway**: sua versão do LiteLLM pode não
  proxyar `/audio/transcriptions` e `/images/generations`. O smoke cai
  automaticamente para as **rotas diretas** (`:18001` / `:18002`) — que também
  estão comentadas em `examples/cutcast.env`.

- **Registry retorna 401**: use virtual key (`sk-...`), não a master key. Confirme
  `metadata.app_id` na key e que o gateway está healthy.

- **Registry DB não existe** (volume Postgres antigo): crie manualmente — ver
  [REGISTRY.md](docs/REGISTRY.md#banco-de-dados).

- **Bind mounts no Windows**: os caminhos relativos dos compose
  (`../../config/models`, `../../config/ollama`) funcionam no Docker Desktop;
  use sempre `/` nos paths (nunca `\`).

---

## Documentação

- [Arquitetura e orçamento de VRAM](docs/architecture.md)
- [Adicionando um modelo](docs/adding-a-model.md)
- [Integrando um projeto](docs/integrating-a-project.md)
- [Model Registry — API de modelos dinâmicos](docs/REGISTRY.md)

## Licença

MIT — veja [LICENSE](LICENSE).
