#!/bin/bash
set -e

# Configuration
REGISTRY_URL="nebulascout/kijani-kiosk" 

# Script the version string (Dynamic Computation)
# Extract VERSION from package.json using node (reliable parsing)
VERSION=$(node -p "require('../kijanikiosk-payments/package.json').version")

# Get 7-character short GITSHA of HEAD
GITSHA=$(git rev-parse --short HEAD)

# Construct the final tag
IMAGE_TAG="${VERSION}-${GITSHA}"
FULL_IMAGE="${REGISTRY_URL}:${IMAGE_TAG}"

echo "Building image: ${FULL_IMAGE}"

# Build the image
# Pass metadata as labels for traceability (optional but recommended)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_DIR="${SCRIPT_DIR}/../kijanikiosk-payments"
DOCKERFILE_DIR="${SCRIPT_DIR}/../containers"

docker build \
  --build-arg VERSION="${VERSION}" \
  --build-arg GITSHA="${GITSHA}" \
  -f "${DOCKERFILE_DIR}/Dockerfile.production" \
  -t "${FULL_IMAGE}" \
  "${APP_DIR}"


echo "Pushing image to registry..."
docker push "${FULL_IMAGE}"

# Verify Source of Truth (Delete Local & Pull Fresh)
echo "Verifying registry is the source of truth..."

# Remove the local image forcefully to ensure we don't run from cache
docker rmi -f "${FULL_IMAGE}"

# Confirm it is gone locally 
if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "${FULL_IMAGE}"; then
  echo "ERROR: Failed to remove local image."
  exit 1
fi

# Pull fresh from the registry
echo "Pulling fresh image from registry..."
docker pull "${FULL_IMAGE}"

# Final Verification
echo "Success! Image ${FULL_IMAGE} is verified from the registry."
