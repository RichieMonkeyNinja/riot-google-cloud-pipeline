# GCP Architecture

## What we are building

A small batch data pipeline that collects official League of Legends data from
the Riot Games API, keeps an immutable raw copy, creates analysis-ready tables,
and lets us query the result in BigQuery.

```text
Riot Games API
      |
      v
Python extractor --> GCS raw bucket --> PySpark transformation --> GCS curated bucket
                                                                    |
                                                                    v
                                                               BigQuery tables
                                                                    |
                                                                    v
                                                            SQL analysis / dashboard
```

## Why each piece exists

| Component | Job | Why we use it |
| --- | --- | --- |
| Riot Games API | Source data | Official source; requires an API key. |
| Python extractor | Ingestion | Calls the API and saves the unchanged response. |
| GCS raw bucket | Landing zone | Lets us replay or debug a load without calling the API again. |
| PySpark job | Transformation | Teaches distributed-data patterns even when our first dataset is small. |
| GCS curated bucket | Prepared files | Stores cleaned, partitioned Parquet files for efficient loading. |
| BigQuery | Warehouse | Runs SQL analysis without managing database servers. |
| Terraform | Infrastructure as Code | Records and recreates cloud resources consistently. |

## Initial dataset and transformation

Start with one region and a small list of summoner or champion identifiers.
The extractor will retrieve match metadata and details. The first transformation
will flatten match JSON into a `match_participants` table: one row per player in
a match, including champion, win/loss, kills, deaths, assists, game duration,
and match date.

This is intentionally simple: it teaches nested JSON, schemas, Parquet, and SQL
without needing a huge dataset. We can later add daily partitions and aggregate
tables such as champion win rate by patch.

## GCP resources Terraform should create

- A GCP project or a supplied existing project (Terraform will not create a
  billing account).
- Required APIs: Cloud Storage, BigQuery, Dataproc Serverless, Secret Manager,
  and Service Usage.
- Two uniquely named GCS buckets: `raw` and `curated`.
- A BigQuery dataset and tables or external-table definitions.
- A least-privilege service account for the pipeline, with only the storage,
  BigQuery, Dataproc, and Secret Manager roles it needs.
- A Secret Manager secret that holds the Riot API key. Terraform creates the
  secret container only; add the secret value outside Terraform so it never
  lands in state.

## Step-by-step build order

1. Run the reproducible Ubuntu-on-WSL bootstrap script below. It installs `uv`,
   Python 3.11, Google Cloud CLI, Terraform, and Java 17. Use `uv` to manage
   PySpark and every other Python package; do not use `pip` or a separately-
   created virtual environment. Use Application Default Credentials locally.
2. Create/select a GCP project with billing enabled and choose a region. The
   initial configuration uses `us-east1` (South Carolina).
3. Obtain a Riot Games development API key, keep it private, and store it in
   Secret Manager. Development keys expire, so failed API calls may simply mean
   the key needs replacing.
4. Write and run the extractor locally. Save each immutable match once under a
   stable raw GCS path such as `raw/matches/match_id=NA1_123.json`.
5. Run the PySpark job locally first. Validate row counts and data types, then
   write partitioned Parquet to the curated bucket.
6. Load or expose the curated data in BigQuery and run a few SQL checks.
7. Move the PySpark job to Dataproc Serverless once the local version is
   understood.
8. Add scheduling, monitoring, and cleanup only after the manual pipeline is
   reliable.

## First ingestion: NA1 Gold I ranked-solo cohort

The primary Python script reads the first ten Gold I entries from NA1, requests
up to twenty recent ranked-solo matches for each player, removes duplicate match
IDs, and writes unchanged match JSON to the raw bucket. It obtains the API key
from Secret Manager, so neither the command nor the source code contains a
secret.

From Ubuntu on WSL, synchronise the locked dependencies, then obtain the bucket
name Terraform created:

```bash
uv sync
RAW_BUCKET="$(cd terraform && terraform output -raw raw_bucket_name)"
PROJECT_ID="$(gcloud config get-value project)"
```

Run the Gold I extractor. The default values are the agreed sample size: ten
players and twenty matches per player. The rate limiter pauses for 1.3 seconds
between Riot requests, so the run can take about five minutes. This is normal
and protects a development key from rate limiting:

```bash
uv run python src/extract_gold_matches.py \
  --project-id "$PROJECT_ID" \
  --raw-bucket "$RAW_BUCKET" \
  --player-count 10 \
  --matches-per-player 20
```

The raw bucket is idempotent: a repeated run checks for the canonical match-ID
file first, and GCS also applies a create-only guard if two runs overlap. A
separate small manifest records what each run found, uploaded, and skipped.
This means `matches/` is the source data for Spark; `ingestion-runs/` is only
an audit trail.

Verify the files arrived:

```bash
gcloud storage ls "gs://$RAW_BUCKET/matches/**"
gcloud storage ls "gs://$RAW_BUCKET/ingestion-runs/**"
```

### First Dataproc Silver rebuild

Dataproc Serverless starts temporary Spark compute, runs the PySpark program,
then stops it. The first real run reads all canonical files in `matches/` and
uses `overwrite` intentionally: because the raw collection itself contains
only one file per match ID, rebuilding Silver produces the same clean result
on every repeat. This costs a small Dataproc batch charge while it runs.

```bash
bash scripts/submit_bronze_to_silver.sh
```

The helper writes two date-partitioned Parquet folders in the curated bucket:
`silver/silver_matches/` and `silver/silver_participants/`. Confirm the batch
finished before continuing to BigQuery:

```bash
gcloud dataproc batches list --region us-east1 --limit 5
```

The PySpark source itself is published by Terraform to the versioned
`pipeline-artifacts` bucket. This gives both a manual Dataproc command and a
future Airflow/Composer DAG one stable URI, rather than requiring either to
access a student's laptop. The staging bucket remains temporary and deletes
objects after seven days.

## dbt Cloud Run package

The dbt project has a separate Docker image because dbt's dependencies should
not be mixed with PySpark or the Riot extractor. The image contains only the
reviewed dbt models, tests, its `uv.lock`, and a Cloud Run profile. At runtime
dbt uses Cloud Run's attached service account through Application Default
Credentials; no browser login or service-account key is baked into the image.

Build the image remotely and then deploy its immutable digest through
Terraform:

```bash
bash scripts/publish_dbt_image.sh
```

## Docker package for ingestion

A Docker image is a reproducible Linux box described by `Dockerfile`. A
container is one temporary running copy of that image. We package only the
Riot ingestion script here; Spark stays outside this image because Dataproc
will run the PySpark transformation separately.

`Dockerfile` copies the exact dependency lockfile first, then runs
`uv sync --locked --no-dev`. This means students who build the same commit use
the same resolved Python packages. `.dockerignore` is the guard at the door:
it prevents API keys, local credentials, Terraform state, test fixtures, and
generated data from being sent to Docker during the build.

Build the local image from Ubuntu on WSL:

```bash
bash scripts/build_ingestion_image.sh
```

This creates the local image `lol-riot-ingestion:local`. Prove its entrypoint
starts without making an API call or using a credential:

```bash
docker run --rm lol-riot-ingestion:local --help
```

Do not put a Riot key, Application Default Credentials, or a company SSL
certificate into this image. Cloud Run will receive its Google identity from a
service account and will read the Riot key from Secret Manager at runtime.

### Publish the image with Cloud Build

Artifact Registry is Google's private shelf for Docker images. Cloud Build is
Google's remote builder: it sends the safe Docker build context to GCP, runs
the same `Dockerfile`, and pushes the image to that shelf. This lets another
student publish an image without installing Docker locally.

First create the Terraform-managed Artifact Registry repository. Then publish
one uniquely tagged development image:

```bash
bash scripts/publish_ingestion_image.sh
```

The helper prints an image reference ending in `@sha256:...`. This digest is
the exact immutable image Cloud Run should use later; do not deploy a mutable
`latest` tag.

### Create the Cloud Run ingestion Job

Cloud Run **Jobs** run one container to completion and then stop. This is a
better fit than a Cloud Run web service because the extractor has no website:
it fetches matches, writes raw JSON, and exits.

Pass the immutable image reference printed by the publishing helper into
Terraform. This creates the job but does not execute it yet:

```bash
terraform -chdir=terraform apply \
  -var='ingestion_image=IMAGE_REPOSITORY/riot-ingestion@sha256:IMAGE_DIGEST'
```

The job uses the existing `lol-pipeline` service account, not your local ADC
mount. Google provides that identity automatically when Cloud Run starts the
container. Its first manual execution is the next verification step; only an
execution, not job creation, consumes Cloud Run container time.

### Schedule daily ingestion

Cloud Scheduler is the alarm clock. It does not fetch Riot data itself; at
02:00 every day in Malaysia it sends an authenticated OAuth request that starts
the Cloud Run Job. It uses a separate scheduler service account with only
`roles/run.invoker` on this one job, so the alarm clock cannot read the Riot
key or write files.

The Terraform schedule is `0 2 * * *` in `Asia/Kuala_Lumpur` and has one
retry. Apply it using the same immutable image digest used to create the job.
After applying, Cloud Scheduler runs at its next scheduled time. Use the Cloud
Console or `gcloud scheduler jobs run lol-riot-ingestion-daily --location=us-east1`
only when you deliberately want another real ingestion execution.

## Local mock data

When the Riot API cannot be reached, use
`tests/fixtures/match_NA1_0000000001.json` to develop the transformation
locally. It is fake data with the same important Match-V5 shape: `metadata`,
`info`, ten `participants`, and two `teams`. It contains no real player data,
API key, or cloud dependency.

## First local PySpark transformation

First, run the bronze-to-silver job using the fake match. It filters missing
identifiers, champion names, and negative combat statistics; removes duplicate
`(match_id, participant_id)` rows; rejects incomplete normal (`CLASSIC`) games;
and calculates KDA, CS, and damage per minute. One valid nested JSON match
becomes one `silver_matches` row and ten `silver_participants` rows. The output
is Parquet, a compact analytics file format. `data/` is ignored by Git, so
local generated output will not be committed accidentally.

```bash
uv sync
uv run python src/transform_matches.py \
  --input tests/fixtures/match_NA1_0000000001.json \
  --output data/silver
```

The command prints a validation summary ending with `silver_matches=1` and
`silver_participants=10`. Look at the two output folders:

```bash
find data/silver -maxdepth 3 -type f
```

Run it a second time only with `--mode overwrite`; this deliberately prevents
an accidental overwrite by default:

```bash
uv run python src/transform_matches.py \
  --input tests/fixtures/match_NA1_0000000001.json \
  --output data/silver \
  --mode overwrite
```

Run the automated validation tests with pytest:

```bash
uv run pytest
```

Later, replace `--input` with a directory of JSON downloaded from the raw GCS
bucket and replace `--output` with the curated GCS bucket path. The script's
input and output paths were designed to support both local paths and `gs://`
paths; Cloud execution needs the GCS Spark connector, which we will configure
when moving this job to Dataproc Serverless.

## Upload the mock pipeline to GCS and BigQuery

After the local transformation works, run the repeatable loader from Ubuntu on
WSL:

```bash
bash scripts/load_mock_to_gcp.sh
```

It performs four small, visible actions:

1. uploads the unchanged fake JSON to the **raw** bucket;
2. uploads the clean Parquet folders to the **curated** bucket;
3. creates or replaces BigQuery `lol_analytics.silver_matches`;
4. creates or replaces BigQuery `lol_analytics.silver_participants`.

`--replace` means this demo loader treats the local files as the complete
sample. It replaces only those two tables, never the dataset or buckets. The
files use `game_date=...` folders, so BigQuery reads `game_date` as a partition
column during the load.

Check that BigQuery can read the loaded player rows:

```bash
bq query --use_legacy_sql=false '
SELECT champion_name, COUNT(*) AS player_rows, COUNTIF(won) AS wins
FROM `lol_analytics.silver_participants`
GROUP BY champion_name
ORDER BY wins DESC, champion_name
'
```

## First Dataproc Serverless run

Dataproc Serverless is the cloud version of our local PySpark command. It
temporarily starts managed Spark workers, reads the mock raw JSON from GCS,
writes silver Parquet to GCS, then stops. The Terraform staging bucket stores
only temporary job files and driver logs; its lifecycle rule deletes them after
seven days.

First apply the new Terraform bucket after reviewing the plan:

```bash
cd terraform
terraform fmt -check
terraform validate
terraform plan
terraform apply
cd ..
```

Then submit one manual, mock-data batch. It has a 20-minute safety timeout and
overwrites only the curated `silver/` prefix:

```bash
bash scripts/submit_bronze_to_silver.sh
```

Watch a submitted batch by replacing `BATCH_ID` with the printed identifier:

```bash
gcloud dataproc batches describe BATCH_ID --region us-east1
```

After it succeeds, reload the two BigQuery silver tables from the curated
bucket, then rebuild dbt gold tables. We will add a dedicated cloud-only loader
next; do not run `load_mock_to_gcp.sh` after the Dataproc batch because that
demo script copies local files back over the cloud output.

## Reproducible local setup (Ubuntu on WSL 2)

WSL 2 with Ubuntu is the project’s required development environment. You may
keep the repository on the Windows drive and access it from Ubuntu. In an
Administrator PowerShell window, install WSL 2 once:

```powershell
wsl --install -d Ubuntu
```

Restart Windows if prompted, open **Ubuntu** from the Start menu, then change
to this repository. Quote the path because the Windows username contains a
space:

```bash
cd "/mnt/c/Users/Richie Teoh/Downloads/codebase-proj/gcp-self"
bash scripts/bootstrap-ubuntu.sh
```

The script uses Ubuntu’s package manager and the official repositories to
install public tooling: `uv`, Python 3.11, Java 17, Terraform, and Google Cloud
CLI. It does **not** create a cloud project, enable billing, authenticate you,
or handle API keys; those actions are tied to an individual account and must
stay outside the repository. Verify the installation in the Ubuntu terminal:

```bash
uv --version
gcloud --version
terraform version
java -version
```

After creating a billed project, initialize the CLI in Ubuntu. Use
`--console-only`: a minimal WSL terminal may not have a Linux browser, so this
prints a sign-in link for you to copy into your normal Windows browser. Then
obtain local Application Default Credentials for Python and Terraform. Replace
the placeholder with your project ID, not a secret:

```bash
gcloud init --console-only
gcloud auth application-default login --no-launch-browser
gcloud config set project YOUR_PROJECT_ID
```

## Security and cost guardrails

- Put `.env`, service-account JSON files, Terraform state files, and generated
  local data in `.gitignore`; do not put secrets in source code or commits.
- Use a small test dataset first. Dataproc Serverless and BigQuery processing
  can incur charges; GCS also charges for stored data and some operations.
- Set a GCP budget alert before testing cloud execution.
- Apply Terraform only after reviewing `terraform plan`; destroy temporary
  resources when the lesson is over.

## Definition of done for the first milestone

- Terraform can create the non-secret infrastructure.
- One successful raw API response exists in the raw bucket.
- The PySpark job produces valid Parquet output with a documented schema.
- BigQuery can answer: "Which champions had the highest win rate in the loaded
  matches?"
- A short README or runbook explains how to repeat and clean up the pipeline.
