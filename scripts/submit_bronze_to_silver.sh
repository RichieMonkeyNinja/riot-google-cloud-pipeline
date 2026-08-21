#!/usr/bin/env bash
# Submit the bronze-to-silver PySpark script as one Dataproc Serverless batch.
# The first real run reads every canonical raw match and rebuilds the silver prefix.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-east1}"
RAW_BUCKET="${RAW_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw raw_bucket_name)}"
CURATED_BUCKET="${CURATED_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw curated_bucket_name)}"
STAGING_BUCKET="${STAGING_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw dataproc_staging_bucket_name)}"
ARTIFACTS_BUCKET="${ARTIFACTS_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw pipeline_artifacts_bucket_name)}"
PIPELINE_SERVICE_ACCOUNT="${PIPELINE_SERVICE_ACCOUNT:-$(terraform -chdir="$TERRAFORM_DIR" output -raw pipeline_service_account_email)}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "No active GCP project. Run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

# `matches/` contains one immutable JSON object per match ID. Do not point
# Spark at `ingestion-runs/`: those files are audit manifests, not match data.
INPUT_PATH="${INPUT_PATH:-gs://$RAW_BUCKET/matches/}"
OUTPUT_PATH="${OUTPUT_PATH:-gs://$CURATED_BUCKET/silver}"
BATCH_ID="${BATCH_ID:-bronze-to-silver-$(date +%Y%m%d-%H%M%S)}"

echo "Submitting Dataproc Serverless batch: $BATCH_ID"
echo "Input:  $INPUT_PATH"
echo "Output: $OUTPUT_PATH"
echo "PySpark code: gs://$ARTIFACTS_BUCKET/pyspark/transform_matches.py"
echo "The batch has a 20-minute safety limit and may incur Dataproc charges."

gcloud dataproc batches submit pyspark "gs://$ARTIFACTS_BUCKET/pyspark/transform_matches.py" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --batch="$BATCH_ID" \
  --version="2.3" \
  --service-account="$PIPELINE_SERVICE_ACCOUNT" \
  --deps-bucket="gs://$STAGING_BUCKET" \
  --staging-bucket="$STAGING_BUCKET" \
  --ttl="20m" \
  --labels="pipeline=lol,layer=bronze-to-silver,environment=dev" \
  -- \
  --input="$INPUT_PATH" \
  --output="$OUTPUT_PATH" \
  --mode=overwrite

echo "Batch submitted. Inspect it with:"
echo "gcloud dataproc batches describe $BATCH_ID --project=$PROJECT_ID --region=$REGION"
