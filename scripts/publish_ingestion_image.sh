#!/usr/bin/env bash
# Build the Riot ingestion Docker image in Cloud Build and publish it to the
# Terraform-managed Artifact Registry repository.
# Usage: bash scripts/publish_ingestion_image.sh [tag]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(terraform -chdir="$TERRAFORM_DIR" output -raw ingestion_image_repository)}"
IMAGE_TAG="${1:-dev-$(date -u +%Y%m%dT%H%M%SZ)}"
IMAGE_URI="$IMAGE_REPOSITORY/riot-ingestion:$IMAGE_TAG"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "No active GCP project. Run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

echo "Cloud Build will build: $IMAGE_URI"
echo "Source directory: $REPO_ROOT"
echo "No Riot key or local Google credential is uploaded because .dockerignore excludes them."

gcloud builds submit "$REPO_ROOT" \
  --project="$PROJECT_ID" \
  --config="$REPO_ROOT/cloudbuild.ingestion.yaml" \
  --substitutions="_IMAGE_URI=$IMAGE_URI"

DIGEST="$(gcloud artifacts docker images describe "$IMAGE_URI" \
  --project="$PROJECT_ID" \
  --format='value(image_summary.digest)')"

echo
echo "Published immutable image reference:"
echo "$IMAGE_REPOSITORY/riot-ingestion@$DIGEST"
