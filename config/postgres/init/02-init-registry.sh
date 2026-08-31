#!/bin/sh
# config/postgres/init/02-init-registry.sh
# Cria role + database dedicados do Model Registry (idempotente).
set -eu

REGISTRY_DB_USER="${REGISTRY_DB_USER:-registry}"
REGISTRY_DB_PASSWORD="${REGISTRY_DB_PASSWORD:-registry}"
REGISTRY_DB_NAME="${REGISTRY_DB_NAME:-registry}"

echo "[init] Configurando registry role='${REGISTRY_DB_USER}' database='${REGISTRY_DB_NAME}'..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	DO \$do\$
	BEGIN
	  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${REGISTRY_DB_USER}') THEN
	    CREATE ROLE ${REGISTRY_DB_USER} LOGIN PASSWORD '${REGISTRY_DB_PASSWORD}';
	  ELSE
	    ALTER ROLE ${REGISTRY_DB_USER} WITH LOGIN PASSWORD '${REGISTRY_DB_PASSWORD}';
	  END IF;
	END
	\$do\$;

	SELECT 'CREATE DATABASE ${REGISTRY_DB_NAME} OWNER ${REGISTRY_DB_USER}'
	WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${REGISTRY_DB_NAME}')\gexec
EOSQL

echo "[init] Registry DB pronto."
