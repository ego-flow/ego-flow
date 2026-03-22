#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.prod"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd docker
require_cmd git

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi

mkdir -p /opt/egoflow/data/raw
mkdir -p /opt/egoflow/data/datasets
mkdir -p /opt/egoflow/data/redis
mkdir -p /opt/egoflow/data/postgres

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  if [[ -z "${GHCR_USERNAME:-}" ]]; then
    echo "GHCR_USERNAME is required when GHCR_TOKEN is provided."
    exit 1
  fi

  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
fi

cd "$REPO_ROOT"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans
docker image prune -f
