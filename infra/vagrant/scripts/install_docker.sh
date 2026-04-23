#!/usr/bin/env bash
#
# install_docker.sh
# -----------------
# Installs Docker Engine + Compose plugin on Ubuntu using Docker's
# official apt repository. Idempotent.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Whether to add the default vagrant user to the docker group.
# Set ADD_VAGRANT_TO_DOCKER=false in the environment to disable.
ADD_VAGRANT_TO_DOCKER="${ADD_VAGRANT_TO_DOCKER:-true}"

KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="${KEYRING_DIR}/docker.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/docker.list"

# -----------------------------------------------------------------------------
# Short-circuit if Docker + Compose plugin are already installed.
# -----------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "[docker] already installed: $(docker --version)"
else
  # ---------------------------------------------------------------------------
  # Add Docker's official GPG key
  # ---------------------------------------------------------------------------
  install -m 0755 -d "${KEYRING_DIR}"

  if [ ! -s "${KEYRING_FILE}" ]; then
    curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
      | gpg --dearmor -o "${KEYRING_FILE}"
    chmod a+r "${KEYRING_FILE}"
  fi

  # ---------------------------------------------------------------------------
  # Add Docker apt repository
  # ---------------------------------------------------------------------------
  # shellcheck disable=SC1091
  . /etc/os-release
  ARCH="$(dpkg --print-architecture)"
  REPO_LINE="deb [arch=${ARCH} signed-by=${KEYRING_FILE}] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"

  if [ ! -f "${SOURCES_FILE}" ] || ! grep -qF "${REPO_LINE}" "${SOURCES_FILE}"; then
    echo "${REPO_LINE}" > "${SOURCES_FILE}"
  fi

  apt-get update -y

  # ---------------------------------------------------------------------------
  # Install Docker Engine + Compose plugin
  # ---------------------------------------------------------------------------
  apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
fi

# -----------------------------------------------------------------------------
# Enable + start Docker
# -----------------------------------------------------------------------------
systemctl enable docker
systemctl start docker

# -----------------------------------------------------------------------------
# Optionally add the 'vagrant' user to the docker group
# -----------------------------------------------------------------------------
if [ "${ADD_VAGRANT_TO_DOCKER}" = "true" ] && id -u vagrant >/dev/null 2>&1; then
  if ! id -nG vagrant | tr ' ' '\n' | grep -qx docker; then
    usermod -aG docker vagrant
    echo "[docker] added 'vagrant' to docker group (requires re-login to take effect)."
  fi
fi

echo "[docker] install complete: $(docker --version)"
echo "[docker] compose: $(docker compose version)"
