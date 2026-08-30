# Integrando um projeto

Qualquer projeto consome esta plataforma como se fosse a **API da OpenAI**.
Só precisa de duas coisas:

```bash
OPENAI_BASE_URL=http://HOST:4000/v1
OPENAI_API_KEY=<virtual key do projeto>
```

E usar os **nomes lógicos** como `model` (`chat-cuts`, `vision-default`,
`whisper`, `image-thumbs`). O projeto **não sabe** qual backend responde.

## Host-ports vs nome de serviço na rede

- **Fora do Docker** (app roda no host): use `http://localhost:4000/v1`
  (ou o IP do host).
- **Dentro do Docker** (app em outro compose): conecte à rede externa
  `localai_net` e use o nome do serviço: `http://gateway:4000/v1`.

```yaml
# no docker-compose.yml do seu projeto
services:
  meu-app:
    environment:
      OPENAI_BASE_URL: http://gateway:4000/v1
      OPENAI_API_KEY: ${OPENAI_API_KEY}
    networks: [localai_net]
networks:
  localai_net:
    external: true
    name: localai_net
```

## Criar a virtual key do projeto

```bash
curl -X POST http://HOST:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "models": ["chat-cuts","vision-default","whisper","image-thumbs"],
        "rpm_limit": 60,
        "tpm_limit": 200000,
        "max_parallel_requests": 2,
        "metadata": {"project": "meu-app"}
      }'
```

A resposta traz `"key": "sk-..."`. Entregue essa key ao projeto.

## Rotas diretas (fallback áudio/imagem)

Se a versão fixada do LiteLLM **não** proxyar áudio/imagem, use as rotas
diretas dos backends (documente ambos os caminhos no seu projeto):

| Rota lógica (gateway)         | Rota direta (fallback)                         |
|-------------------------------|------------------------------------------------|
| `POST /v1/audio/transcriptions` | `http://HOST:18001/v1/audio/transcriptions`  |
| `POST /v1/images/generations`   | `http://HOST:18002/v1/images/generations`    |

`chat` e `visão` sempre passam pelo gateway (`/v1/chat/completions`).

## Exemplo: CutCast

O CutCast normalmente define chaves `LOCAL_*` e monta o client via
`build_ai_client`. Basta mapear para o gateway:

| Variável CutCast          | Valor                              |
|---------------------------|------------------------------------|
| `LOCAL_CHAT_BASE_URL`     | `http://HOST:4000/v1`              |
| `LOCAL_CHAT_MODEL`        | `chat-cuts`                        |
| `LOCAL_VISION_MODEL`      | `vision-default`                   |
| `LOCAL_TRANSCRIBE_MODEL`  | `whisper`                          |
| `LOCAL_IMAGE_MODEL`       | `image-thumbs`                     |
| `LOCAL_AI_API_KEY`        | `<virtual key gerada acima>`       |

Ver `examples/cutcast.env`. `build_ai_client` deve usar `LOCAL_CHAT_BASE_URL`
como `base_url` e `LOCAL_AI_API_KEY` como `api_key`, escolhendo o modelo pelo
nome lógico conforme a etapa do pipeline.
