#!/usr/bin/env bash
set -euo pipefail

# Changes PostgreSQL password inside the running container, updates .env,
# and recreates Zabbix server/web so they use the new password.
# Does NOT wipe the database (unlike ./install.sh reset).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ ! -f .env ]]; then
  die "No existe .env"
fi

if ! docker info >/dev/null 2>&1; then
  die "Docker no está corriendo"
fi

if ! docker inspect zabbix-postgres >/dev/null 2>&1; then
  die "zabbix-postgres no está arriba. Primero: ./install.sh"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

COMPOSE=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
fi

NEW_PASS="${1:-}"
if [[ -z "${NEW_PASS}" ]]; then
  read -r -s -p "Nueva contraseña de PostgreSQL: " NEW_PASS
  echo
  read -r -s -p "Repite la contraseña: " NEW_PASS2
  echo
  [[ "${NEW_PASS}" == "${NEW_PASS2}" ]] || die "No coinciden"
fi

[[ -n "${NEW_PASS}" ]] || die "La contraseña no puede estar vacía"
if [[ "${NEW_PASS}" == *'$'* || "${NEW_PASS}" == *'`'* || "${NEW_PASS}" == *$'\n'* ]]; then
  die "No uses \$, backticks ni saltos de línea (rompen .env / Compose)."
fi

ESC="${NEW_PASS//\'/\'\'}"

echo "Cambiando clave del usuario ${POSTGRES_USER} en PostgreSQL..."
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" zabbix-postgres \
  psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${ESC}';" >/dev/null

export NEW_PG_PASS="${NEW_PASS}"
python3 - <<'PY'
from pathlib import Path
import os

path = Path(".env")
new = os.environ["NEW_PG_PASS"]
lines = []
found = False
for line in path.read_text().splitlines(keepends=True):
    if line.startswith("POSTGRES_PASSWORD="):
        nl = "\n" if line.endswith("\n") else ""
        lines.append(f"POSTGRES_PASSWORD={new}{nl}")
        found = True
    else:
        lines.append(line)
if not found:
    lines.append(f"POSTGRES_PASSWORD={new}\n")
path.write_text("".join(lines))
PY
unset NEW_PG_PASS NEW_PASS ESC

echo "Actualizado .env. Recreando zabbix-server y zabbix-web..."
"${COMPOSE[@]}" up -d --force-recreate --no-deps zabbix-server zabbix-web

echo
echo "Listo. La base NO se borró."
echo "Zabbix ya usa la nueva POSTGRES_PASSWORD de .env."
echo "La clave de la web (Admin) no cambió."
