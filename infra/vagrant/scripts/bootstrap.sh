#!/usr/bin/env bash
#
# bootstrap.sh
# ------------
# Prepares a fresh Ubuntu VM with the base packages we generally want on
# a server / CI deploy target. Safe to run multiple times.

set -euo pipefail

# Force noninteractive apt behavior so provisioning never blocks on a prompt
# (e.g. grub, tzdata, conffile questions).
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# -----------------------------------------------------------------------------
# Package index refresh
# -----------------------------------------------------------------------------
apt-get update -y

# -----------------------------------------------------------------------------
# Base packages
# -----------------------------------------------------------------------------
# Kept intentionally small. These are tools we expect on any deploy target:
#   - ca-certificates, curl, gnupg, lsb-release: required to add 3rd party repos
#   - git:        needed to clone app/config repos
#   - jq:         handy for JSON parsing in deploy scripts
#   - unzip, tar: common extraction utilities
#   - rsync:      useful for syncing deployment artifacts
#   - htop:       lightweight diagnostic tool
#   - openssh-client: ssh/git+ssh operations
#   - software-properties-common: apt-add-repository helper
BASE_PACKAGES=(
  ca-certificates
  curl
  gnupg
  lsb-release
  git
  jq
  unzip
  tar
  rsync
  htop
  openssh-client
  software-properties-common
)

# `apt-get install -y` is already idempotent: already-installed packages
# are simply skipped. We still guard with `--no-install-recommends` to keep
# the image small.
apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}"

# -----------------------------------------------------------------------------
# Housekeeping
# -----------------------------------------------------------------------------
apt-get autoremove -y
apt-get clean

echo "[bootstrap] base packages installed."
