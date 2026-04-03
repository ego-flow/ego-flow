#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_BASE_FILE="$REPO_ROOT/ego-flow-server/compose.yml"
COMPOSE_PROD_FILE="$REPO_ROOT/ego-flow-server/compose.prod.yml"
CONFIG_ROOT="${CONFIG_ROOT:-/opt/egoflow/config}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/egoflow/releases}"
APP_ENV_FILE="$CONFIG_ROOT/.env"
COMPOSE_ENV_FILE="$CONFIG_ROOT/.env.compose"
CONFIG_FILE="$CONFIG_ROOT/config.json"
VERBOSE_DEPLOY="${VERBOSE_DEPLOY:-1}"
TRACE_DEPLOY="${TRACE_DEPLOY:-1}"
CURRENT_ACTION=""

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd docker
require_cmd curl

compose_cmd() {
  docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_BASE_FILE" -f "$COMPOSE_PROD_FILE" "$@"
}

print_header() {
  local title="$1"
  printf '\n=== %s ===\n' "$title"
}

trace_on() {
  if [[ "$TRACE_DEPLOY" == "1" ]]; then
    set -x
  fi
}

trace_off() {
  if [[ "$TRACE_DEPLOY" == "1" ]]; then
    set +x
  fi
}

dump_compose_diagnostics() {
  print_header "docker compose ps"
  compose_cmd ps || true

  local service
  for service in backend worker dashboard proxy mediamtx postgres redis; do
    print_header "${service} logs"
    compose_cmd logs --tail=200 "$service" || true
  done

  local container
  for container in \
    ego-flow-server-backend-1 \
    ego-flow-server-worker-1 \
    ego-flow-server-dashboard-1 \
    ego-flow-server-proxy-1 \
    ego-flow-server-mediamtx-1 \
    ego-flow-server-postgres-1 \
    ego-flow-server-redis-1
  do
    print_header "${container} health"
    docker inspect "$container" --format '{{json .State.Health}}' 2>/dev/null || true
  done
}

on_error() {
  local exit_code="$1"
  local line_no="$2"

  trace_off
  echo "deploy.sh failed during '${CURRENT_ACTION:-unknown}' at line ${line_no} with exit code ${exit_code}"
  dump_compose_diagnostics
  exit "$exit_code"
}

trap 'on_error $? $LINENO' ERR

read_compose_value() {
  local key="$1"
  local default_value="$2"
  local value

  value="$(sed -nE "s/^${key}=(.+)$/\\1/p" "$COMPOSE_ENV_FILE" | tail -n1)"

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default_value"
  fi
}

read_config_number() {
  local key="$1"
  local default_value="$2"
  local value

  value="$(
    tr -d '\n' < "$CONFIG_FILE" |
      sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/p"
  )"

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default_value"
  fi
}

if [[ ! -f "$APP_ENV_FILE" ]]; then
  echo "Missing env file: $APP_ENV_FILE"
  exit 1
fi

if [[ ! -f "$COMPOSE_ENV_FILE" ]]; then
  echo "Missing compose env file: $COMPOSE_ENV_FILE"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE"
  exit 1
fi

if [[ ! -f "$COMPOSE_BASE_FILE" ]]; then
  echo "Missing compose file: $COMPOSE_BASE_FILE"
  exit 1
fi

if [[ ! -f "$COMPOSE_PROD_FILE" ]]; then
  echo "Missing compose file: $COMPOSE_PROD_FILE"
  exit 1
fi

export PUBLIC_HTTP_PORT
export RTMP_PORT
export HLS_PORT
export CONFIG_ROOT
export RELEASES_ROOT
export DATA_ROOT

PUBLIC_HTTP_PORT="$(read_config_number "PUBLIC_HTTP_PORT" "80")"
RTMP_PORT="$(read_config_number "RTMP_PORT" "1935")"
HLS_PORT="$(read_config_number "HLS_PORT" "8888")"
DATA_ROOT="$(read_compose_value "DATA_ROOT" "/opt/egoflow/data")"

mkdir -p "$CONFIG_ROOT"
mkdir -p "$RELEASES_ROOT"

mkdir -p "$DATA_ROOT/raw"
mkdir -p "$DATA_ROOT/datasets"
mkdir -p "$DATA_ROOT/redis"
mkdir -p "$DATA_ROOT/postgres"

current_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

current_git_sha() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

record_release_metadata() {
  local backend_image dashboard_image deployed_at release_dir metadata_file latest_file git_sha

  backend_image="$(sed -nE 's/^BACKEND_IMAGE=(.+)$/\1/p' "$COMPOSE_ENV_FILE" | tail -n1)"
  dashboard_image="$(sed -nE 's/^DASHBOARD_IMAGE=(.+)$/\1/p' "$COMPOSE_ENV_FILE" | tail -n1)"
  deployed_at="$(current_timestamp)"
  git_sha="$(current_git_sha)"
  release_dir="$RELEASES_ROOT/release-${deployed_at//[:]/-}"
  metadata_file="$release_dir/metadata.json"
  latest_file="$RELEASES_ROOT/latest.json"

  mkdir -p "$release_dir"
  cp "$CONFIG_FILE" "$release_dir/config.json"
  cp "$APP_ENV_FILE" "$release_dir/.env"
  cp "$COMPOSE_ENV_FILE" "$release_dir/.env.compose"
  chmod 600 "$release_dir/config.json" "$release_dir/.env" "$release_dir/.env.compose"

  cat > "$metadata_file" <<EOF
{
  "deployed_at": "$deployed_at",
  "git_sha": "$git_sha",
  "backend_image": "${backend_image:-unknown}",
  "dashboard_image": "${dashboard_image:-unknown}",
  "config_root": "$CONFIG_ROOT",
  "data_root": "$DATA_ROOT",
  "release_dir": "$release_dir",
  "config_snapshot": {
    "config_json": "$release_dir/config.json",
    "app_env": "$release_dir/.env",
    "compose_env": "$release_dir/.env.compose"
  },
  "public_http_port": $PUBLIC_HTTP_PORT,
  "rtmp_port": $RTMP_PORT,
  "hls_port": $HLS_PORT
}
EOF

  cp "$metadata_file" "$latest_file"
}

check_http_status() {
  local url="$1"
  local expected_pattern="$2"
  local status

  status="$(curl -ksS -o /dev/null -w '%{http_code}' "$url")"
  if [[ ! "$status" =~ $expected_pattern ]]; then
    echo "Smoke test failed for $url (status: $status)"
    exit 1
  fi
}

smoke_test() {
  CURRENT_ACTION="smoke-test"
  compose_cmd ps
  check_http_status "http://127.0.0.1:${PUBLIC_HTTP_PORT}/api/v1/health" '^(200)$'
  check_http_status "http://127.0.0.1:${PUBLIC_HTTP_PORT}/api-docs" '^(200|301|302|307|308)$'
  check_http_status "http://127.0.0.1:${PUBLIC_HTTP_PORT}/login" '^(200|301|302|307|308)$'
  check_http_status "http://127.0.0.1:${HLS_PORT}/" '^(200|404)$'
}

deploy_stack() {
  CURRENT_ACTION="deploy"

  if [[ "$VERBOSE_DEPLOY" == "1" ]]; then
    print_header "deploy context"
    echo "repo_root=$REPO_ROOT"
    echo "config_root=$CONFIG_ROOT"
    echo "releases_root=$RELEASES_ROOT"
    echo "data_root=$DATA_ROOT"
    echo "public_http_port=$PUBLIC_HTTP_PORT"
    echo "rtmp_port=$RTMP_PORT"
    echo "hls_port=$HLS_PORT"
    echo "git_sha=$(current_git_sha)"
    print_header "compose config"
    compose_cmd config
  fi

  if [[ -n "${GHCR_TOKEN:-}" ]]; then
    if [[ -z "${GHCR_USERNAME:-}" ]]; then
      echo "GHCR_USERNAME is required when GHCR_TOKEN is provided."
      exit 1
    fi

    trace_off
    printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
    trace_on
  fi

  cd "$REPO_ROOT"
  trace_on
  compose_cmd pull
  compose_cmd up -d --remove-orphans
  trace_off
  if [[ "$VERBOSE_DEPLOY" == "1" ]]; then
    dump_compose_diagnostics
  fi
  record_release_metadata
  docker image prune -f
}

cmd="${1:-deploy}"
case "$cmd" in
  deploy)
    deploy_stack
    ;;
  smoke-test)
    cd "$REPO_ROOT"
    smoke_test
    ;;
  *)
    echo "Usage: deploy.sh [deploy|smoke-test]"
    exit 1
    ;;
esac
