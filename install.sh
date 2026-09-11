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
Usage: ./install.sh [command]

Commands:
  (none)   Install Docker deps check, create .env, pull images, start stack
  up       Start (or recreate) containers
  down     Stop containers (keeps database volume)
  logs     Follow logs
  status   Show container status
  reset    Stop and DELETE the database volume (fresh Zabbix)

EOF
}

need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. On Debian run: sudo ./prepare.sh"
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but the daemon is not running."
    echo "Try: sudo systemctl start docker"
    echo "If you just ran prepare.sh, log out and back in (docker group)."
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not available. On Debian run: sudo ./prepare.sh"
    exit 1
  fi
}

ensure_env() {
  if [[ -f .env ]]; then
    echo "Using existing .env"
    return
  fi

  local template=""
  if [[ -f env.example ]]; then
    template="env.example"
  elif [[ -f .env.example ]]; then
    template=".env.example"
  else
    echo "Missing env.example"
    exit 1
  fi

  local password
  password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${password}/" "${template}" > .env
  echo "Created .env with a generated PostgreSQL password."
}

load_env() {
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
}

print_access() {
  load_env
  cat <<EOF

Zabbix is up.

  Web UI:     http://localhost:${ZABBIX_WEB_PORT:-8080}
  Web user:   Admin
  Web pass:   zabbix

  PostgreSQL (inside Docker network):
    host:     postgres
    db:       ${POSTGRES_DB}
    user:     ${POSTGRES_USER}
    password: ${POSTGRES_PASSWORD}

The web password is a Zabbix default, not the database password.
Change Admin in the UI after first login.

EOF
}

wait_for_web() {
  load_env
  local url="http://127.0.0.1:${ZABBIX_WEB_PORT:-8080}"
  echo "Waiting for the web UI at ${url} ..."
  local i
  for i in $(seq 1 90); do
    if curl -fsS "${url}/" >/dev/null 2>&1 || curl -fsS "${url}/ping" >/dev/null 2>&1; then
      echo "Web UI is responding."
      return 0
    fi
    sleep 2
  done
  echo "Containers started, but the web UI is not answering yet. Check: ${COMPOSE[*]} logs -f"
  return 0
}

cmd_up() {
  need_docker
  ensure_env
  echo "Pulling images..."
  "${COMPOSE[@]}" pull
  echo "Starting stack..."
  "${COMPOSE[@]}" up -d
  wait_for_web
  print_access
  "${COMPOSE[@]}" ps
}

cmd_down() {
  need_docker
  "${COMPOSE[@]}" down
  echo "Stopped. Database volume was kept."
}

cmd_reset() {
  need_docker
  echo "This deletes the PostgreSQL volume (all Zabbix history and config)."
  "${COMPOSE[@]}" down -v
  echo "Volumes removed. Run ./install.sh to start clean."
}

cmd="${1:-install}"
case "$cmd" in
  -h|--help|help)
    usage
    ;;
  install|up)
    cmd_up
    ;;
  down|stop)
    cmd_down
    ;;
  logs)
    need_docker
    "${COMPOSE[@]}" logs -f
    ;;
  status|ps)
    need_docker
    "${COMPOSE[@]}" ps
    ;;
  reset)
    cmd_reset
    ;;
  *)
    usage
    exit 1
    ;;
esac
