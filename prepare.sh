#!/usr/bin/env bash
set -euo pipefail

# Prepares Debian 11–13: Docker Engine + Compose plugin.
# Run: sudo ./prepare.sh
# Then log out/in (if you were added to the docker group) and run ./install.sh

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo ./prepare.sh"
  fi
}

check_debian() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS. This script supports Debian 11, 12 and 13."
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "debian" ]]; then
    die "Detected '${ID:-unknown}', expected Debian. Aborting."
  fi

  local major="${VERSION_ID%%.*}"
  case "${major}" in
    11|12|13) ;;
    *)
      die "Debian ${VERSION_ID:-?} is not supported. Use Debian 11 (bullseye), 12 (bookworm) or 13 (trixie)."
      ;;
  esac

  CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "${CODENAME}" ]]; then
    CODENAME="trixie"
  fi
  ARCH="$(dpkg --print-architecture)"
  log "OS: Debian ${VERSION_ID:-?} (${CODENAME}), arch ${ARCH}"
}

remove_conflicting() {
  log "Removing conflicting Docker packages if present..."
  apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc >/dev/null 2>&1 || true
}

install_prereqs() {
  log "Installing prerequisites..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
}

add_docker_repo() {
  log "Adding Docker apt repository..."
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update -y
}

install_docker() {
  log "Installing Docker Engine and Compose plugin..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
}

enable_docker() {
  log "Enabling Docker service..."
  systemctl enable --now docker
}

add_user_to_group() {
  local target_user="${SUDO_USER:-}"
  if [[ -z "${target_user}" || "${target_user}" == "root" ]]; then
    log "Running as root with no sudo user. Skip docker group (use sudo docker, or add a user later)."
    return
  fi
  if getent group docker >/dev/null; then
    usermod -aG docker "${target_user}"
    log "Added '${target_user}' to group docker."
    log "Log out and back in (or reboot) before ./install.sh without sudo."
  fi
}

verify() {
  log "Verifying..."
  docker --version
  docker compose version
  systemctl is-active --quiet docker || die "Docker service is not active."
  log "Docker is running."
}

need_root
check_debian
remove_conflicting
install_prereqs
add_docker_repo
install_docker
enable_docker
add_user_to_group
verify

cat <<'EOF'

Prepare done.

Next:
  1. If you were added to the docker group, log out and log in again.
  2. cd to this project
  3. cp env.example .env   # optional: set your POSTGRES_PASSWORD
  4. ./install.sh

EOF
