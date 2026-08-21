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
4. Write and run the extractor locally. Save date-stamped JSON files under a
   raw GCS path such as `raw/match-details/ingest_date=YYYY-MM-DD/`.
5. Run the PySpark job locally first. Validate row counts and data types, then
   write partitioned Parquet to the curated bucket.
6. Load or expose the curated data in BigQuery and run a few SQL checks.
7. Move the PySpark job to Dataproc Serverless once the local version is
   understood.
8. Add scheduling, monitoring, and cleanup only after the manual pipeline is
   reliable.

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
