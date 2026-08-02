#!/usr/bin/env bash
# scripts/deploy-app.sh
# Deploys a versioned kk-api artifact to the blue or green environment.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
APP_VERSION="${APP_VERSION:-v1.3.0}"
DEPLOY_ENV="${DEPLOY_ENV:-blue}"
ARTIFACT_BASE_URL="${ARTIFACT_BASE_URL:-http://127.0.0.1:8080}"
BLUE_PORT="${BLUE_PORT:-3000}"
GREEN_PORT="${GREEN_PORT:-3001}"

# Derived variables
ARTIFACT_NAME="kk-api-${APP_VERSION}.tar.gz"
CHECKSUM_NAME="${ARTIFACT_NAME}.sha256"
SERVICE_NAME="kk-api-${DEPLOY_ENV}.service"
TARGET_DIR="/opt/kijanikiosk/${DEPLOY_ENV}/app"
TEMP_DIR="/tmp/kk-api-deploy-$$"

# Validate DEPLOY_ENV
case "${DEPLOY_ENV}" in
  blue|green) ;;
  *) echo "ERROR: DEPLOY_ENV must be 'blue' or 'green', got '${DEPLOY_ENV}'"; exit 1 ;;
esac

# ── Logging ──────────────────────────────────────────────────────────────────
SCRIPT_START=$(date +%s)

log() {
  local elapsed=$(( $(date +%s) - SCRIPT_START ))
  echo "[$(date -u +%H:%M:%S)] [+${elapsed}s] $*"
}

log_fail() {
  echo "[$(date -u +%H:%M:%S)] [FAIL] $*" >&2
}

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

# ── Phase Functions ──────────────────────────────────────────────────────────

fetch_artifact() {
  log "Fetching artifact..."
  mkdir -p "${TEMP_DIR}"
  
  local url="${ARTIFACT_BASE_URL}/${ARTIFACT_NAME}"
  local checksum_url="${ARTIFACT_BASE_URL}/${CHECKSUM_NAME}"

  # Download artifact
  if ! curl -fsSL -o "${TEMP_DIR}/${ARTIFACT_NAME}" "${url}"; then
    log_fail "Failed to download artifact from ${url}"
    exit 1
  fi

  # Download checksum file
  if ! curl -fsSL -o "${TEMP_DIR}/${CHECKSUM_NAME}" "${checksum_url}"; then
    log_fail "Failed to download checksum from ${checksum_url}"
    exit 1
  fi
  
  log "Artifact downloaded successfully."
}

validate_artifact() {
  log "Validating artifact integrity..."
  cd "${TEMP_DIR}"
  
  # Verify checksum
  if ! sha256sum -c "${CHECKSUM_NAME}" > /dev/null 2>&1; then
    log_fail "Checksum validation failed for ${ARTIFACT_NAME}"
    exit 1
  fi
  
  log "Checksum verified."
}

deploy_artifact() {
  log "Deploying artifact to ${TARGET_DIR}..."
  
  # Ensure target directory exists
  sudo mkdir -p "${TARGET_DIR}"
  
  # Extract artifact (strip top-level directory if present)
  # Using --strip-components=1 assumes the tarball contains a root folder like kk-api-v1.4.0/
  # If your tarball extracts files directly, remove --strip-components=1
  sudo tar -xzf "${TEMP_DIR}/${ARTIFACT_NAME}" -C "${TARGET_DIR}" --strip-components=1
  
  # Set ownership
  sudo chown -R kk-api:kk-api "${TARGET_DIR}"
  
  # Update version file
  echo "${APP_VERSION}" | sudo tee /opt/kijanikiosk/${DEPLOY_ENV}/.version > /dev/null
  
  log "Artifact deployed to ${TARGET_DIR}"
}

restart_service() {
  log "Restarting service ${SERVICE_NAME}..."
  
  sudo systemctl daemon-reload
  sudo systemctl restart "${SERVICE_NAME}"
  
  # Wait briefly for startup
  sleep 2
  
  log "Service restart triggered."
}

verify_service() {
  log "Verifying service health..."
  
  local port
  if [ "${DEPLOY_ENV}" = "blue" ]; then
    port="${BLUE_PORT}"
  else
    port="${GREEN_PORT}"
  fi
  
  local max_attempts=10
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    if curl -fsSL "http://127.0.0.1:${port}/health" > /dev/null 2>&1; then
      log "Health check passed on port ${port}"
      return 0
    fi
    log "Attempt ${attempt}/${max_attempts}: Service not ready yet..."
    sleep 2
    ((attempt++))
  done
  
  log_fail "Service failed to become healthy after ${max_attempts} attempts."
  systemctl status "${SERVICE_NAME}" --no-pager
  exit 1
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=== kk-api Deployment Script ==="
  log "Version: ${APP_VERSION}"
  log "Target:  ${DEPLOY_ENV} (port: $([ "${DEPLOY_ENV}" = "blue" ] && echo "${BLUE_PORT}" || echo "${GREEN_PORT}"))"
  log "Artifact: ${ARTIFACT_BASE_URL}/${ARTIFACT_NAME}"
  echo ""

  fetch_artifact 
  validate_artifact
  deploy_artifact
  restart_service
  verify_service

  echo ""
  log "=== Deployment complete: kk-api ${APP_VERSION} on ${DEPLOY_ENV} ==="
  exit 0
}

main "$@"   