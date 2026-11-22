#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${BASE_DIR}/docker-compose.prod.yml"
ENV_FILE="${BASE_DIR}/.env"

# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env_file "${ENV_FILE}"

LOCAL_PORT="${PENPOT_LOCAL_PORT:-9001}"
UNHEALTHY_CONTAINERS="$(dc ps --filter "health=unhealthy" -q)"

if [[ -n "${UNHEALTHY_CONTAINERS}" ]]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WATCHDOG] Found unhealthy containers. Triggering restart..."
  for cid in ${UNHEALTHY_CONTAINERS}; do
    NAME="$(docker inspect --format '{{.Name}}' "${cid}")"
    echo "Restarting unhealthy container: ${NAME}"
    docker restart "${cid}"
  done
  exit 0
fi

# Probe loopback readiness endpoint
READY=0
for _ in 1 2 3; do
  if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/readyz" > /dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 3
done

if [[ ${READY} -eq 0 ]]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WATCHDOG] Penpot frontend failed readiness probe at http://127.0.0.1:${LOCAL_PORT}/readyz"
  dc restart penpot-frontend penpot-backend
fi
