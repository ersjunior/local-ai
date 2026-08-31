#!/bin/sh
# config/postgres/init/01-init.sh
#
# Init idempotente do servidor Postgres compartilhado.
# Roda SÓ na 1ª criação do volume (docker-entrypoint-initdb.d).
# Cria o role + database dedicados do LiteLLM lendo variáveis do ambiente
# (POSTGRES_USER é o superusuário; LITELLM_DB_* vêm do .env via compose).
#
# Padrão do stack: 1 database + 1 role por aplicação, no MESMO servidor.
# Para adicionar uma app nova, veja o TEMPLATE comentado no fim do arquivo.
set -eu

LITELLM_DB_USER="${LITELLM_DB_USER:-litellm}"
LITELLM_DB_PASSWORD="${LITELLM_DB_PASSWORD:-litellm}"
LITELLM_DB_NAME="${LITELLM_DB_NAME:-litellm}"

echo "[init] Configurando role='${LITELLM_DB_USER}' e database='${LITELLM_DB_NAME}'..."

# Conecta como superusuário (via socket) no db padrão e cria role+db se faltarem.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	-- Role (idempotente): cria se não existir; senão, só garante a senha/login.
	DO \$do\$
	BEGIN
	  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${LITELLM_DB_USER}') THEN
	    CREATE ROLE ${LITELLM_DB_USER} LOGIN PASSWORD '${LITELLM_DB_PASSWORD}';
	  ELSE
	    ALTER ROLE ${LITELLM_DB_USER} WITH LOGIN PASSWORD '${LITELLM_DB_PASSWORD}';
	  END IF;
	END
	\$do\$;

	-- Database (idempotente): CREATE DATABASE não roda em bloco DO, então usamos \gexec.
	SELECT 'CREATE DATABASE ${LITELLM_DB_NAME} OWNER ${LITELLM_DB_USER}'
	WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${LITELLM_DB_NAME}')\gexec
EOSQL

echo "[init] Pronto."

# ==========================================================================
# TEMPLATE — adicionar uma NOVA aplicação (novo role + novo database).
# Escale copiando o bloco abaixo (ou rode via psql depois; ver docs).
#
#   NOVA_APP_USER=minhaapp
#   NOVA_APP_PASSWORD=trocar
#   NOVA_APP_DB=minhaapp
#   psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
#     DO \$do\$
#     BEGIN
#       IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${NOVA_APP_USER}') THEN
#         CREATE ROLE ${NOVA_APP_USER} LOGIN PASSWORD '${NOVA_APP_PASSWORD}';
#       END IF;
#     END
#     \$do\$;
#     SELECT 'CREATE DATABASE ${NOVA_APP_DB} OWNER ${NOVA_APP_USER}'
#     WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${NOVA_APP_DB}')\gexec
#   EOSQL
#
# Em SQL puro (config/postgres/init/02-...sql), o equivalente seria:
#   -- CREATE ROLE minhaapp LOGIN PASSWORD 'trocar';
#   -- CREATE DATABASE minhaapp OWNER minhaapp;
# ==========================================================================
