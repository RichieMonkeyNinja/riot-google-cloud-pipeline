# League of Legends GCP data pipeline

A learning project that turns League of Legends match data into analytics-ready
BigQuery tables. It is designed to be reproducible from a clean clone without
committing API keys, credentials, generated data, or Terraform state.

```text
Riot API
   -> Cloud Run ingestion
   -> GCS raw JSON
   -> Dataproc Serverless / PySpark
   -> GCS curated Parquet (Silver)
   -> BigQuery (Silver)
   -> dbt on Cloud Run (Gold)
```

Cloud Composer is an
optional Airflow demonstration environment; it is disabled by default because
it has an hourly cost while it exists.

![alt text](<images/gcp_architecture_v2.png>)

## What this project demonstrates

- `uv` for locked Python dependencies and virtual environments.
- PySpark validation, deduplication, and Parquet output.
- GCS Bronze/Raw and Silver storage layers.
- BigQuery Silver tables and dbt Gold models/tests.
- Docker, Cloud Build, Artifact Registry, and Cloud Run Jobs.
- Terraform-managed GCP infrastructure and least-privilege service accounts.
- Optional Airflow orchestration with Cloud Composer.

## Repository map

| Path | Purpose |
| --- | --- |
| `src/` | Riot ingestion and PySpark transformation code. |
| `tests/` | pytest tests and safe mock match data. |
| `terraform/` | GCP infrastructure and its detailed setup/destroy guide. |
| `dbt/` | BigQuery dbt project, models, and tests. |
| `airflow/` | Local Airflow rehearsal and the Composer DAG. |
| `scripts/` | Repeatable helpers for publishing images and submitting Spark. |
| `ARCHITECTURE.md` | Detailed design and beginner walkthrough. |

## Quick local check

Use Ubuntu on WSL 2, even if this repository stays on your Windows drive.

```bash
cd "/mnt/c/Users/YOUR_WINDOWS_USER/path/to/gcp-self"
uv sync
uv run pytest
```

This runs offline tests only. It does not call Riot or create GCP resources.

## Before using GCP

You need:

1. A GCP project with billing enabled.
2. Google Cloud CLI authenticated in WSL.
3. Application Default Credentials for local Terraform and Python.
4. A Riot API key stored only in Secret Manager.

```bash
gcloud auth application-default login --no-launch-browser
gcloud config set project YOUR_PROJECT_ID
```

Terraform intentionally needs immutable Cloud Run image digests. Follow the
service-specific publishing steps before applying infrastructure; do not use a
mutable `latest` image tag.

## Documentation

- [Architecture and learning walkthrough](ARCHITECTURE.md)
- [Terraform setup, Composer demo, and safe teardown](terraform/README.md)
- [Local Airflow rehearsal](airflow/README.md)
- [dbt project](dbt/README.md)

## Safety and cost notes

- Never commit a Riot API key, `.env` file, credentials, or Terraform state.
- Riot development API keys expire every 24 hours; add a new Secret Manager
  version when a key expires.
- Cloud Run and Dataproc charge only while jobs run. Cloud Composer charges
  while its environment exists, even when no DAG runs.
- Review `terraform plan` before applying. To remove only the optional Composer
  demo, use `enable_composer_demo=false`; do not run a broad `terraform destroy`
  unless you intend to remove the whole project infrastructure.
