#!/usr/bin/env bash
#
# configure_user.sh
# -----------------
# Prepares directory layout and ownership for future deployment work.
# Intentionally does NOT handle secrets, SSH keys, or user creation.

set -euo pipefail

# Target user that will own the deploy directory. Defaults to the standard
# Vagrant box user. Override with DEPLOY_USER env var if needed.
DEPLOY_USER="${DEPLOY_USER:-vagrant}"

# Base directory for deployment artifacts inside the VM.
DEPLOY_ROOT="/opt/deploy"

# Subdirectories we expect later stages (compose stacks, env files,
# release bundles, backups) to use.
SUBDIRS=(
  "${DEPLOY_ROOT}/app"      # compose stack + rendered configs
  "${DEPLOY_ROOT}/env"      # .env files (NOT committed, NOT populated here)
  "${DEPLOY_ROOT}/releases" # historical release tarballs / image refs
  "${DEPLOY_ROOT}/backups"  # local backups prior to redeploy
  "${DEPLOY_ROOT}/logs"     # app / deployment logs
)

# -----------------------------------------------------------------------------
# Ensure deploy user exists (it should, on a stock Vagrant box).
# -----------------------------------------------------------------------------
if ! id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  echo "[configure-user] user '${DEPLOY_USER}' does not exist; skipping chown."
  DEPLOY_USER=""
fi

# -----------------------------------------------------------------------------
# Create directories with safe permissions.
# -----------------------------------------------------------------------------
install -d -m 0755 "${DEPLOY_ROOT}"

for d in "${SUBDIRS[@]}"; do
  install -d -m 0755 "${d}"
done

# env/ is more sensitive (will hold .env later) -> tighten perms.
chmod 0750 "${DEPLOY_ROOT}/env"

# -----------------------------------------------------------------------------
# Ownership
# -----------------------------------------------------------------------------
if [ -n "${DEPLOY_USER}" ]; then
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_ROOT}"
fi

echo "[configure-user] deploy directory layout ready at ${DEPLOY_ROOT}"
