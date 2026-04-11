#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/ego-flow-server"

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  echo "Expected a git checkout at: $ROOT_DIR"
  exit 1
fi

if [[ ! -x "$SERVER_DIR/scripts/run.sh" ]]; then
  echo "Missing server run script: $SERVER_DIR/scripts/run.sh"
  exit 1
fi

cd "$ROOT_DIR"

if [[ -f "$SERVER_DIR/config.json" && -f "$SERVER_DIR/.env" && -f "$SERVER_DIR/compose.yml" ]]; then
  echo "[stack] Stopping current stack..."
  (
    cd "$SERVER_DIR"
    ./scripts/run.sh down
  )
else
  echo "[stack] Skipping shutdown because ego-flow-server/config.json or .env is missing."
fi

echo "[git] Pulling parent repository..."
git pull --ff-only

echo "[git] Syncing submodules..."
git submodule sync --recursive
git submodule update --init --recursive

echo "[stack] Starting updated stack..."
(
  cd "$SERVER_DIR"
  ./scripts/run.sh up
)
