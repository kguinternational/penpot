#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${BASE_DIR}/docker-compose.prod.yml"
ENV_FILE="${BASE_DIR}/.env"

# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
load_env_file "${ENV_FILE}"

BACKUP_DIR="${PENPOT_BACKUP_DIR:-${BASE_DIR}/backups}"
RETENTION_DAYS="${PENPOT_BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="${BACKUP_DIR}/${TIMESTAMP}"

mkdir -p "${TARGET_DIR}"

echo "==> [$(date +'%Y-%m-%d %H:%M:%S')] Starting Penpot 24/7 backup to ${TARGET_DIR}..."

# 1. PostgreSQL Database Dump
echo "--> Backing up PostgreSQL database..."
POSTGRES_USER="${POSTGRES_USER:-penpot}"
DB_DUMP_FILE="${TARGET_DIR}/postgres_${TIMESTAMP}.sql.gz"

if ! dc exec -T penpot-postgres pg_dump --clean --if-exists -U "${POSTGRES_USER}" penpot | gzip > "${DB_DUMP_FILE}"; then
  echo "ERROR: PostgreSQL backup failed!" >&2
  exit 1
fi
echo "    PostgreSQL backup complete: $(du -h "${DB_DUMP_FILE}" | cut -f1)"

# 2. Penpot Assets Volume Backup
echo "--> Backing up Penpot assets volume..."
ASSETS_DUMP_FILE="${TARGET_DIR}/assets_${TIMESTAMP}.tar.gz"
BACKEND_CID="$(dc ps -a -q penpot-backend)"

if [[ -z "${BACKEND_CID}" ]]; then
  echo "ERROR: penpot-backend container not found; cannot locate assets volume." >&2
  exit 1
fi

if ! docker run --rm \
  --volumes-from "${BACKEND_CID}" \
  alpine tar -czf - -C /opt/data/assets . > "${ASSETS_DUMP_FILE}"; then
  echo "ERROR: Assets volume backup failed!" >&2
  exit 1
fi
echo "    Assets backup complete: $(du -h "${ASSETS_DUMP_FILE}" | cut -f1)"

# 3. Generate SHA256 Checksums
echo "--> Generating checksums..."
(cd "${TARGET_DIR}" && sha256_gen "$(basename "${DB_DUMP_FILE}")" "$(basename "${ASSETS_DUMP_FILE}")" > SHA256SUMS)

# 4. Prune old backups according to retention policy
echo "--> Pruning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -exec rm -rf {} +

echo "==> [$(date +'%Y-%m-%d %H:%M:%S')] Backup finished successfully!"
