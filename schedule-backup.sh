#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="${ROOT}/backup.sh"
MARKER="# zabbix-docker-backup"

usage() {
  cat <<'EOF'
Usage: ./schedule-backup.sh [option]

You can run this as many times as you want. Each run REPLACES the previous
schedule. There is only one backup job at a time.

  (no args)   Interactive menu
  hourly      Every 60 minutes
  6h          Every 6 hours
  daily       Every day at 03:00 (server time)
  2d          Every 2 days at 03:00
  weekly      Sundays at 03:00
  off         Remove scheduled backup
  now         Run a backup immediately
  status      Show current cron line

Flexible:
  ./schedule-backup.sh every 60 minutes
  ./schedule-backup.sh every 6 hours
  ./schedule-backup.sh every 2 days

Custom cron:
  ./schedule-backup.sh cron "0 4 * * *"
EOF
}

need_cron() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "cron is not installed. On Debian: sudo apt-get install -y cron && sudo systemctl enable --now cron"
    exit 1
  fi
}

current_crontab() {
  crontab -l 2>/dev/null || true
}

strip_marker() {
  current_crontab | grep -v "${MARKER}" || true
}

install_line() {
  local spec="$1"
  local line="${spec} ${BACKUP} ${MARKER}"
  chmod +x "${BACKUP}"
  local tmp
  tmp="$(mktemp)"
  strip_marker > "${tmp}"
  echo "${line}" >> "${tmp}"
  crontab "${tmp}"
  rm -f "${tmp}"
  echo "Previous backup schedule (if any) was replaced."
  echo "Scheduled: ${line}"
  echo "Dumps go to: ${ROOT}/backups"
  echo "Check anytime with: ./schedule-backup.sh status"
}

remove_schedule() {
  local tmp
  tmp="$(mktemp)"
  strip_marker > "${tmp}"
  crontab "${tmp}"
  rm -f "${tmp}"
  echo "Scheduled backup removed."
}

show_status() {
  local line
  line="$(current_crontab | grep "${MARKER}" || true)"
  if [[ -z "${line}" ]]; then
    echo "No backup schedule installed."
  else
    echo "Current schedule (only this job; next run of this script replaces it):"
    echo "  ${line}"
  fi
}

cron_every() {
  local n="$1"
  local unit="$2"
  if ! [[ "${n}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Need a positive number. Example: ./schedule-backup.sh every 60 minutes"
    exit 1
  fi
  unit="$(printf '%s' "${unit}" | tr '[:upper:]' '[:lower:]')"
  case "${unit}" in
    minute|minutes|min|mins|m)
      if [[ "${n}" -eq 60 ]]; then
        install_line "0 * * * *"
      elif [[ $((60 % n)) -eq 0 ]]; then
        install_line "*/${n} * * * *"
      else
        echo "Minutes must divide 60 (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60)."
        exit 1
      fi
      ;;
    hour|hours|h)
      if [[ "${n}" -eq 1 ]]; then
        install_line "0 * * * *"
      elif [[ "${n}" -lt 24 ]]; then
        install_line "0 */${n} * * *"
      else
        echo "Hours must be between 1 and 23."
        exit 1
      fi
      ;;
    day|days|d)
      if [[ "${n}" -eq 1 ]]; then
        install_line "0 3 * * *"
      else
        install_line "0 3 */${n} * *"
      fi
      ;;
    *)
      echo "Unit must be minutes, hours or days."
      exit 1
      ;;
  esac
}

menu() {
  cat <<'EOF'

Cada vez que ejecutas este script se REEMPLAZA la programación anterior.
Solo queda una.

  1) Cada 60 minutos
  2) Cada 6 horas
  3) Cada dia a las 03:00
  4) Cada 2 dias a las 03:00
  5) Cada semana (domingo 03:00)
  6) Quitar programacion
  7) Backup ahora (no cambia el horario)
  8) Ver programacion actual
  0) Cancelar

EOF
  local choice
  read -r -p "Elige [0-8]: " choice
  case "${choice}" in
    1) install_line "0 * * * *" ;;
    2) install_line "0 */6 * * *" ;;
    3) install_line "0 3 * * *" ;;
    4) install_line "0 3 */2 * *" ;;
    5) install_line "0 3 * * 0" ;;
    6) remove_schedule ;;
    7) "${BACKUP}" ;;
    8) show_status ;;
    0) echo "Cancelado." ;;
    *) echo "Opcion invalida."; exit 1 ;;
  esac
}

need_cron
chmod +x "${BACKUP}"

cmd="${1:-}"
case "${cmd}" in
  "") menu ;;
  -h|--help|help) usage ;;
  hourly|60m) install_line "0 * * * *" ;;
  6h) install_line "0 */6 * * *" ;;
  daily) install_line "0 3 * * *" ;;
  2d) install_line "0 3 */2 * *" ;;
  weekly) install_line "0 3 * * 0" ;;
  off|remove) remove_schedule ;;
  now) "${BACKUP}" ;;
  status) show_status ;;
  every)
    if [[ -z "${2:-}" || -z "${3:-}" ]]; then
      echo "Example: ./schedule-backup.sh every 60 minutes"
      echo "         ./schedule-backup.sh every 2 days"
      exit 1
    fi
    cron_every "$2" "$3"
    ;;
  cron)
    if [[ -z "${2:-}" ]]; then
      echo "Missing cron expression. Example: ./schedule-backup.sh cron \"0 4 * * *\""
      exit 1
    fi
    install_line "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
