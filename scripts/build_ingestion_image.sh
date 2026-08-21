#!/usr/bin/env bash
# Build the local Docker image used by the Riot ingestion Cloud Run Job.
# Usage: bash scripts/build_ingestion_image.sh [image-name:tag]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${1:-lol-riot-ingestion:local}"

docker build --tag "$IMAGE_NAME" "$REPO_ROOT"

echo
echo "Built: $IMAGE_NAME"
echo "Safe smoke test (does not call Riot or GCP):"
echo "docker run --rm $IMAGE_NAME --help"
