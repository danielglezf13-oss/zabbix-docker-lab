#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

KEEP="${BACKUP_KEEP:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST_DIR="${ROOT}/backups"
mkdir -p "${DEST_DIR}"
FILE="${DEST_DIR}/zabbix-${STAMP}.sql.gz"
LOG="${DEST_DIR}/backup.log"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running."
  exit 1
fi

if ! docker inspect zabbix-postgres >/dev/null 2>&1; then
  echo "Container zabbix-postgres is not running. Start with ./install.sh"
  exit 1
fi

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup -> ${FILE}"
  docker exec -t zabbix-postgres pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip -c > "${FILE}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK $(du -h "${FILE}" | awk '{print $1}')"

  if [[ "${KEEP}" =~ ^[0-9]+$ ]] && [[ "${KEEP}" -gt 0 ]]; then
    extra="$(ls -1t "${DEST_DIR}"/zabbix-*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)) || true)"
    if [[ -n "${extra}" ]]; then
      echo "${extra}" | xargs rm -f
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removed old dumps (keep ${KEEP})"
    fi
  fi
} | tee -a "${LOG}"

echo "Backup saved: ${FILE}"
