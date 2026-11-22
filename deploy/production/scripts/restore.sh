#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${BASE_DIR}/docker-compose.prod.yml"
ENV_FILE="${BASE_DIR}/.env"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path_to_backup_directory_or_timestamp> [--force]"
  echo "Example: $0 ./backups/20261103_040000 --force"
  exit 1
fi

BACKUP_PATH="$1"
FORCE="${2:-}"

if [[ ! -d "${BACKUP_PATH}" ]]; then
  if [[ -d "${BASE_DIR}/backups/${BACKUP_PATH}" ]]; then
    BACKUP_PATH="${BASE_DIR}/backups/${BACKUP_PATH}"
  else
    echo "ERROR: Backup directory '${BACKUP_PATH}' does not exist!" >&2
    exit 1
  fi
fi

# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env_file "${ENV_FILE}"

if [[ -f "${BACKUP_PATH}/SHA256SUMS" ]]; then
  echo "==> Verifying backup checksums..."
  (cd "${BACKUP_PATH}" && sha256_check SHA256SUMS)
fi

if [[ "${FORCE}" != "--force" ]]; then
  read -rp "WARNING: Restoring will overwrite existing database and assets. Proceed? [y/N]: " confirm
  if [[ "${confirm}" != [yY] && "${confirm}" != [yY][eE][sS] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

POSTGRES_USER="${POSTGRES_USER:-penpot}"

DB_FILE="$(find "${BACKUP_PATH}" -maxdepth 1 -name "postgres_*.sql.gz" | head -n 1)"
ASSETS_FILE="$(find "${BACKUP_PATH}" -maxdepth 1 -name "assets_*.tar.gz" | head -n 1)"

if [[ -z "${DB_FILE}" || ! -f "${DB_FILE}" ]]; then
  echo "ERROR: Database backup file not found in ${BACKUP_PATH}!" >&2
  exit 1
fi

echo "==> Stopping application services..."
dc stop penpot-backend penpot-frontend penpot-exporter penpot-admin-console

echo "==> Restoring database from ${DB_FILE}..."
gunzip -c "${DB_FILE}" | dc exec -T penpot-postgres psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" penpot

if [[ -n "${ASSETS_FILE}" && -f "${ASSETS_FILE}" ]]; then
  BACKEND_CID="$(dc ps -a -q penpot-backend)"
  if [[ -z "${BACKEND_CID}" ]]; then
    echo "ERROR: penpot-backend container not found; cannot locate assets volume." >&2
    exit 1
  fi
  echo "==> Restoring assets from ${ASSETS_FILE}..."
  docker run --rm -i \
    --volumes-from "${BACKEND_CID}" \
    alpine sh -c "find /opt/data/assets -mindepth 1 -delete && tar -xzf - -C /opt/data/assets" < "${ASSETS_FILE}"
fi

echo "==> Restarting services..."
dc start penpot-backend penpot-frontend penpot-exporter penpot-admin-console

echo "==> Restore finished successfully!"
