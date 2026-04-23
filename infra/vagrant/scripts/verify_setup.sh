#!/usr/bin/env bash
#
# verify_setup.sh
# ---------------
# Smoke-check that the VM is correctly provisioned. Exits nonzero on
# any failure so that `vagrant up` / `vagrant provision` will surface it.

set -euo pipefail

fail() {
  echo "[verify] FAIL: $*" >&2
  exit 1
}

section() {
  echo "----- $* -----"
}

# -----------------------------------------------------------------------------
# Tool versions
# -----------------------------------------------------------------------------
section "uname"
uname -a || fail "uname not available"

section "git"
command -v git  >/dev/null || fail "git not installed"
git --version

section "curl"
command -v curl >/dev/null || fail "curl not installed"
curl --version | head -n1

section "docker"
command -v docker >/dev/null || fail "docker not installed"
docker --version

section "docker compose"
docker compose version >/dev/null || fail "docker compose plugin missing"
docker compose version

# -----------------------------------------------------------------------------
# Docker daemon health
# -----------------------------------------------------------------------------
section "docker daemon"
if ! systemctl is-active --quiet docker; then
  fail "docker service is not active"
fi

# `docker info` requires either root or docker-group membership. During
# provisioning this runs as root, so it is a valid health check.
if ! docker info >/dev/null 2>&1; then
  fail "docker daemon is not responding to 'docker info'"
fi

echo "[verify] OK: all checks passed."
