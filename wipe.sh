#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

COMPOSE=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  fi
fi

usage() {
  cat <<'EOF'
Usage: ./wipe.sh [level]

Cleans this Zabbix stack when something went wrong.

  data     Stop containers and DELETE the PostgreSQL volume (same as ./install.sh reset)
  stack    data + delete dumps in backups/ + remove backup cron
  images   stack + delete Docker images used by this compose file
  (none)   Interactive menu

Docker Engine itself is NOT uninstalled. See INSTRUCCIONES.md for that.
EOF
}

need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Nothing to wipe at container level."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running. Try: sudo systemctl start docker"
    exit 1
  fi
  return 0
}

wipe_cron() {
  if [[ -x ./schedule-backup.sh ]]; then
    ./schedule-backup.sh off || true
  fi
}

wipe_backups() {
  if [[ -d backups ]]; then
    rm -f backups/zabbix-*.sql.gz backups/backup.log
    echo "Removed dumps in backups/"
  fi
}

wipe_data() {
  need_docker || return 0
  echo "Stopping containers and deleting the PostgreSQL volume..."
  "${COMPOSE[@]}" down -v
  echo "Database volume removed."
}

wipe_stack() {
  wipe_cron
  wipe_data
  wipe_backups
}

wipe_images() {
  wipe_stack
  if need_docker; then
    echo "Removing images declared in docker-compose.yml..."
    "${COMPOSE[@]}" down --rmi local >/dev/null 2>&1 || true
    docker image rm -f \
      postgres:16-alpine \
      zabbix/zabbix-server-pgsql:alpine-7.0-latest \
      zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest \
      zabbix/zabbix-agent2:alpine-7.0-latest \
      2>/dev/null || true
    echo "Images removed (if they existed)."
  fi
}

menu() {
  cat <<'EOF'

What do you want to delete?

  1) Only the database (containers down + volume). Start again with ./install.sh
  2) Database + local dumps + backup cron
  3) Everything of THIS project (2 + Docker images). Docker Engine stays installed
  0) Cancel

EOF
  local choice
  read -r -p "Choose [0-3]: " choice
  case "${choice}" in
    1) wipe_data ;;
    2) wipe_stack ;;
    3) wipe_images ;;
    0) echo "Cancelled."; return ;;
    *) echo "Invalid option."; exit 1 ;;
  esac
  echo
  echo "Done. To start clean: edit .env if needed, then ./install.sh"
}

cmd="${1:-}"
case "${cmd}" in
  "" ) menu ;;
  -h|--help|help) usage ;;
  data|reset) wipe_data ;;
  stack) wipe_stack ;;
  images|all) wipe_images ;;
  *) usage; exit 1 ;;
esac
