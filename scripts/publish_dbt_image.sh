#!/usr/bin/env bash
# Build the isolated dbt image remotely and print its immutable digest.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-east1}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(terraform -chdir="$TERRAFORM_DIR" output -raw ingestion_image_repository)}"
IMAGE_TAG="${IMAGE_TAG:-dbt-$(date -u +%Y%m%dT%H%M%SZ)}"
IMAGE_URI="$IMAGE_REPOSITORY/dbt-runner:$IMAGE_TAG"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "No active GCP project. Run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

echo "Building dbt image with Cloud Build: $IMAGE_URI"
gcloud builds submit "$REPO_ROOT" \
  --project="$PROJECT_ID" \
  --config="$REPO_ROOT/cloudbuild.dbt.yaml" \
  --substitutions="_IMAGE_URI=$IMAGE_URI"

echo "Resolve the immutable digest before Terraform apply:"
echo "gcloud artifacts docker images describe $IMAGE_URI --format='value(image_summary.digest)'"
