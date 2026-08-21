#!/usr/bin/env bash
# Upload the fake Riot fixture and load its local Parquet output into BigQuery.
# This is a learning/demo loader, not the production scheduler.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"
FIXTURE="$REPO_ROOT/tests/fixtures/match_NA1_0000000001.json"
LOCAL_SILVER="$REPO_ROOT/data/silver"

if [[ ! -f "$FIXTURE" ]]; then
  echo "Missing fake fixture: $FIXTURE" >&2
  exit 1
fi

if [[ ! -d "$LOCAL_SILVER/silver_matches" || ! -d "$LOCAL_SILVER/silver_participants" ]]; then
  echo "Silver Parquet output is missing. Run the bronze-to-silver job first:" >&2
  echo "uv run python src/transform_matches.py --input tests/fixtures/match_NA1_0000000001.json --output data/silver" >&2
  exit 1
fi

# Environment variables are optional overrides. Normally Terraform supplies them.
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
RAW_BUCKET="${RAW_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw raw_bucket_name)}"
CURATED_BUCKET="${CURATED_BUCKET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw curated_bucket_name)}"
DATASET="${DATASET:-$(terraform -chdir="$TERRAFORM_DIR" output -raw bigquery_dataset_id)}"
LOCATION="${LOCATION:-us-east1}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "No active GCP project. Run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

echo "1/4 Uploading the unchanged fake API response to the raw bucket..."
gcloud storage cp "$FIXTURE" \
  "gs://$RAW_BUCKET/match-details/ingest_date=2026-02-02/run_id=mock/match_id=NA1_0000000001.json"

echo "2/4 Syncing validated silver Parquet files to the curated bucket..."
# Spark assigns new part-file names on every run. Mirror these narrow prefixes
# so old Parquet files cannot be loaded alongside the new schema.
gcloud storage rsync --recursive --delete-unmatched-destination-objects \
  "$LOCAL_SILVER/silver_matches" "gs://$CURATED_BUCKET/silver_matches"
gcloud storage rsync --recursive --delete-unmatched-destination-objects \
  "$LOCAL_SILVER/silver_participants" "gs://$CURATED_BUCKET/silver_participants"

# Spark also writes _SUCCESS marker files. BigQuery must receive only real
# Parquet objects so it can see the game_date=... partition folders.
MATCH_URIS="$(gcloud storage ls "gs://$CURATED_BUCKET/silver_matches/game_date=*/*.parquet" | paste -sd, -)"
PARTICIPANT_URIS="$(gcloud storage ls "gs://$CURATED_BUCKET/silver_participants/game_date=*/*.parquet" | paste -sd, -)"
if [[ -z "$MATCH_URIS" || -z "$PARTICIPANT_URIS" ]]; then
  echo "No Parquet files found in the curated bucket after upload." >&2
  exit 1
fi

echo "3/4 Creating or replacing $DATASET.silver_matches..."
bq --location="$LOCATION" load \
  --replace \
  --source_format=PARQUET \
  --hive_partitioning_mode=AUTO \
  --hive_partitioning_source_uri_prefix="gs://$CURATED_BUCKET/silver_matches/" \
  "$PROJECT_ID:$DATASET.silver_matches" \
  "$MATCH_URIS"

echo "4/4 Creating or replacing $DATASET.silver_participants..."
bq --location="$LOCATION" load \
  --replace \
  --source_format=PARQUET \
  --hive_partitioning_mode=AUTO \
  --hive_partitioning_source_uri_prefix="gs://$CURATED_BUCKET/silver_participants/" \
  "$PROJECT_ID:$DATASET.silver_participants" \
  "$PARTICIPANT_URIS"

echo "Done. BigQuery tables: $PROJECT_ID.$DATASET.silver_matches and $PROJECT_ID.$DATASET.silver_participants"
