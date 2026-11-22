#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${BASE_DIR}/docker-compose.prod.yml"
ENV_FILE="${BASE_DIR}/.env"
EXAMPLE_ENV="${BASE_DIR}/.env.production.example"

# shellcheck source=scripts/lib.sh
source "${BASE_DIR}/scripts/lib.sh"

generate_secret_key() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets; print(secrets.token_urlsafe(64))"
  else
    openssl rand -base64 64 | tr -d '\n' | tr '+/' '-_' | tr -d '='
  fi
}

generate_db_password() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets, string; alphabet = string.ascii_letters + string.digits; print(''.join(secrets.choice(alphabet) for _ in range(32)))"
  else
    openssl rand -hex 20
  fi
}

init_env() {
  local force="${1:-}"
  if [[ -f "${ENV_FILE}" && "${force}" != "--force" ]]; then
    echo "ERROR: ${ENV_FILE} already exists. Pass --force to overwrite." >&2
    exit 1
  fi

  local secret_key db_password
  secret_key="$(generate_secret_key)"
  db_password="$(generate_db_password)"

  cp "${EXAMPLE_ENV}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "${ENV_FILE}" "${secret_key}" "${db_password}" <<'PY'
import sys
path, secret, db_pw = sys.argv[1:4]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()
text = text.replace("REPLACE_WITH_STRONG_RANDOM_SECRET_KEY_MIN_64_CHARS", secret, 1)
text = text.replace("REPLACE_WITH_STRONG_DATABASE_PASSWORD", db_pw, 1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
  else
    local tmp_file
    tmp_file="$(mktemp)"
    sed \
      -e "s|REPLACE_WITH_STRONG_RANDOM_SECRET_KEY_MIN_64_CHARS|${secret_key}|" \
      -e "s|REPLACE_WITH_STRONG_DATABASE_PASSWORD|${db_password}|" \
      "${ENV_FILE}" > "${tmp_file}"
    mv "${tmp_file}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
  fi

  echo "==> Created ${ENV_FILE} with generated secrets (chmod 600)."
  echo "==> Review PENPOT_DOMAIN, PENPOT_PUBLIC_URI, ACME_EMAIL, and SMTP settings in ${ENV_FILE}, then run: $0 start"
}

require_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: ${ENV_FILE} not found. Run '$0 init' first." >&2
    exit 1
  fi
  load_env_file "${ENV_FILE}"
}

validate_secrets() {
  if [[ -z "${PENPOT_SECRET_KEY:-}" || "${PENPOT_SECRET_KEY}" == REPLACE_WITH_STRONG_* ]]; then
    echo "ERROR: PENPOT_SECRET_KEY is missing or still uses the placeholder in ${ENV_FILE}." >&2
    exit 1
  fi
  if [[ -z "${POSTGRES_PASSWORD:-}" || "${POSTGRES_PASSWORD}" == REPLACE_WITH_STRONG_* ]]; then
    echo "ERROR: POSTGRES_PASSWORD is missing or still uses the placeholder in ${ENV_FILE}." >&2
    exit 1
  fi
}

cmd="${1:-help}"

case "${cmd}" in
  init)
    init_env "${2:-}"
    ;;

  start|up)
    require_env
    validate_secrets
    echo "==> Starting Penpot 24/7 services..."
    dc up -d --remove-orphans
    echo "==> Services started. Checking container status..."
    dc ps
    ;;

  stop|down)
    require_env
    echo "==> Stopping Penpot services..."
    dc down
    ;;

  restart)
    require_env
    echo "==> Restarting Penpot services..."
    dc restart
    ;;

  status|ps)
    require_env
    dc ps
    ;;

  logs)
    require_env
    shift || true
    dc logs -f "$@"
    ;;

  backup)
    require_env
    "${BASE_DIR}/scripts/backup.sh"
    ;;

  restore)
    require_env
    shift || true
    "${BASE_DIR}/scripts/restore.sh" "$@"
    ;;

  update)
    require_env
    validate_secrets
    echo "==> Pulling latest images..."
    dc pull
    echo "==> Re-creating containers with updated images..."
    dc up -d --remove-orphans
    echo "==> Update complete."
    ;;

  check-ports)
    require_env
    echo "==> Checking port bindings on penpot containers..."
    dc ps --format "table {{.Service}}\t{{.Ports}}"
    ;;

  help|-h|--help)
    echo "Penpot 24/7 Control CLI"
    echo "Usage: $0 {init|start|stop|restart|status|logs|backup|restore|update|check-ports}"
    ;;

  *)
    echo "Penpot 24/7 Control CLI"
    echo "Usage: $0 {init|start|stop|restart|status|logs|backup|restore|update|check-ports}"
    exit 1
    ;;
esac
