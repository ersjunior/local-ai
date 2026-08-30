# Makefile — local-ai
#
# Uso comum:
#   make net           # cria a rede localai_net (uma vez)
#   make up            # sobe o perfil core (gateway + ollama + whisper)
#   make pull          # baixa os pesos dos modelos
#   make create-models # cria aliases do Ollama (cutcast-cuts / cutcast-vision)
#   make smoke         # testa todas as rotas via gateway

SHELL := /bin/bash
COMPOSE := docker compose
GATEWAY ?= http://localhost:4000

# Carrega .env se existir (para GATEWAY_PORT, LITELLM_MASTER_KEY etc.)
ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: net up up-all perf down logs pull create-models smoke key add-model config help

help: ## Lista os alvos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

net: ## Cria a rede externa localai_net (idempotente)
	@docker network inspect localai_net >/dev/null 2>&1 || docker network create localai_net

up: net ## Sobe perfil core (gateway + ollama + whisper)
	$(COMPOSE) --profile core up -d

up-all: net ## Sobe core + image (chat + visão + áudio + imagem)
	$(COMPOSE) --profile core --profile image up -d

perf: net ## Sobe perfil perf (vLLM)
	$(COMPOSE) --profile perf up -d

down: ## Derruba tudo
	$(COMPOSE) --profile core --profile image --profile perf down

logs: ## Segue os logs de todos os serviços
	$(COMPOSE) logs -f

config: ## Valida a composição (docker compose config)
	$(COMPOSE) --profile core --profile image --profile perf config

pull: ## Baixa os pesos dos modelos (scripts/pull-models.sh)
	bash scripts/pull-models.sh

create-models: ## Cria aliases do Ollama a partir dos Modelfiles (aplica params do catálogo)
	docker exec localai-ollama ollama create cutcast-cuts   -f /modelfiles/cutcast-cuts.Modelfile
	docker exec localai-ollama ollama create cutcast-vision -f /modelfiles/cutcast-vision.Modelfile

smoke: ## Roda o smoke-test em todas as rotas (scripts/smoke-test.sh)
	GATEWAY=$(GATEWAY) LITELLM_MASTER_KEY=$(LITELLM_MASTER_KEY) bash scripts/smoke-test.sh

key: ## Cria uma virtual key de exemplo (rpm/tpm) via gateway
	@curl -s -X POST "$(GATEWAY)/key/generate" \
		-H "Authorization: Bearer $(LITELLM_MASTER_KEY)" \
		-H "Content-Type: application/json" \
		-d '{"models":["chat-cuts","vision-default","whisper","image-thumbs"],"rpm_limit":60,"tpm_limit":200000,"max_parallel_requests":2,"metadata":{"project":"example"}}'
	@echo ""

add-model: ## Scaffold de um novo modelo no catálogo (scripts/add-model.sh)
	bash scripts/add-model.sh
