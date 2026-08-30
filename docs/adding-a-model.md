# Adicionando um modelo

O catálogo (`config/models/`) é **desacoplado** dos backends e dos projetos
consumidores. Adicionar um modelo **não exige** mexer em nenhum projeto que
consome o gateway — apenas no gateway.

## Catálogo (documentação) vs Definição real (servida)

Há **dois** diretórios com papéis distintos — não confundir:

| Diretório         | Papel                          | Montagem no LocalAI | No git                    |
|-------------------|--------------------------------|---------------------|---------------------------|
| `config/models/`  | **Catálogo / documentação**    | `/catalog:ro`       | versionado (só docs)      |
| `config/localai/` | **Definição real** (LocalAI)   | `/models` (rw)      | só os `.yaml`; pesos ignorados |

- `config/models/*.yaml` é fonte de verdade/documentação: descreve nome lógico,
  backend, licença etc. **O LocalAI não lê isso como modelo.**
- `config/localai/*.yaml` é o que o **LocalAI realmente carrega** (backend
  `diffusers`). Os pesos baixados do HuggingFace também caem aqui e são
  ignorados pelo git (ver `.gitignore`).

Hoje existem duas definições reais de imagem:
- `config/localai/flux-schnell.yaml` — **PADRÃO** (`image-thumbs → flux-schnell`),
  Apache-2.0. Motivo: o texto do título é **baked pelo app** (PIL), então não
  precisamos da renderização de texto do modelo; FLUX.1-schnell (12B, distilado)
  cabe no 24GB do RTX 4090 e é rápido/confiável.
- `config/localai/qwen-image.yaml` — **alternativa** (melhor texto renderizado
  pelo modelo, porém ~20B, pesado/arriscado em f16 no single-GPU).

**FLUX.1-schnell é gated no HuggingFace**: aceite os termos em
[huggingface.co/black-forest-labs/FLUX.1-schnell](https://huggingface.co/black-forest-labs/FLUX.1-schnell)
e defina `HUGGING_FACE_HUB_TOKEN` no `.env` **antes do primeiro `up` do perfil
image**. Licença dos pesos: Apache-2.0.

Para usar o **qwen-image** no lugar, troque uma linha em
`config/gateway/config.yaml`, na rota `image-thumbs`:

```yaml
      # model: openai/flux-schnell      # comente esta
      model: openai/qwen-image          # descomente esta
```

e reinicie o gateway (`docker compose restart gateway`).

O `make smoke` / `scripts/smoke-test.ps1` valida a rota `image-thumbs` (✅/❌).
Se der **❌**, verifique o token HF (FLUX gated) ou troque de modelo conforme acima.

> `images.edit`/img2img pode não existir na API do LocalAI — o app cai para
> `images.generate`. Para edição fiel, planeje um serviço ComfyUI (TODO).

## Passo a passo

1. **Criar o arquivo no catálogo** (fonte de verdade / documentação):

```bash
bash scripts/add-model.sh <logical_name> <backend> <model_id> [alias]
# ex.: bash scripts/add-model.sh chat-mistral ollama mistral-small:24b
```

Isso cria `config/models/<logical_name>.yaml` e **imprime o bloco `model_list`**
pronto para colar.

2. **Adicionar a rota no gateway**: cole o bloco impresso em
   `config/gateway/config.yaml`, dentro de `model_list`.

3. **(Se for um backend novo)** crie `services/<x>/compose.yaml`, adicione o
   `include:` em `docker-compose.yml` e um `profile:` apropriado.

4. **Baixar os pesos**:

```bash
make pull            # ou o comando específico do backend
```

5. **Validar**:

```bash
make config          # docker compose config
make smoke           # testa as rotas
```

Reinicie o gateway para recarregar o config: `docker compose restart gateway`.

---

## Exemplo A — novo LLM (Ollama)

```bash
bash scripts/add-model.sh chat-mistral ollama mistral-small:24b
# cole o bloco no config.yaml
docker exec localai-ollama ollama pull mistral-small:24b
docker compose restart gateway
```

Bloco gerado:

```yaml
  - model_name: chat-mistral
    litellm_params:
      model: ollama_chat/mistral-small:24b
      api_base: http://ollama:11434
    model_info:
      mode: chat
```

## Exemplo B — novo modelo de imagem (LocalAI)

```bash
bash scripts/add-model.sh image-sdxl localai sdxl
# cole o bloco (mode: image_generation) no config.yaml
# instale o modelo no LocalAI (galeria ou arquivo em /models)
docker compose restart gateway
```

> `images.edit` (img2img) pode não existir na API do LocalAI. Para edição fiel,
> planeje um serviço ComfyUI (TODO em `services/`).

## Exemplo C — novo VLM (visão, Ollama)

```bash
bash scripts/add-model.sh vision-llama ollama llama3.2-vision:11b
docker exec localai-ollama ollama pull llama3.2-vision:11b
docker compose restart gateway
```

Adicione `supports_vision: true` em `model_info` no bloco colado.

---

## Licenças (padrão: só uso comercial)

| Modelo             | Licença                         | Comercial? |
|--------------------|---------------------------------|------------|
| Qwen3 / Qwen3-VL   | Qwen License (com restrições)   | Sim*       |
| Qwen-Image         | Qwen-Image License              | Sim*       |
| gpt-oss-20b        | Apache-2.0                      | Sim        |
| whisper large-v3   | MIT                             | Sim        |
| FLUX.1-dev / 2-dev | Non-commercial                  | **Não**    |

\* verificar as restrições específicas da licença Qwen antes de usar em produto pago.
