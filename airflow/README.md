# Local Airflow rehearsal

This folder is a local rehearsal room for the Cloud Composer DAG. It uses its
own `uv` lock because Airflow has a large, tightly-coupled dependency set that
must not be mixed with the extractor's PySpark dependencies or dbt's runtime.

## Safe first test

The DAG defaults to `run_real_work=false`. It parses and shows the dependency
graph but skips Cloud Run, Dataproc, and BigQuery, so it does not incur GCP
workload charges.

From Ubuntu on WSL:

```bash
cd airflow
docker compose up airflow-init
docker compose up -d
```

Open `http://localhost:8080` and sign in with `airflow` / `airflow`. These are
local-only demonstration credentials, never cloud credentials.

Run a safe command-line test:

```bash
docker compose --profile cli run --rm airflow-cli \
  airflow dags test lol_end_to_end 2026-08-20 \
  --conf '{"run_real_work": false}'
```

To start real GCP work, trigger the DAG in the UI and enter this run
configuration. This starts Cloud Run, Dataproc, and BigQuery jobs and incurs
their normal charges:

```json
{"run_real_work": true}
```

Stop the local rehearsal environment when finished:

```bash
docker compose down
```

`docker compose down -v` also deletes the **local** Postgres history. Use it
only when you deliberately want a clean local Airflow database.

## Before the first real DAG run

The DAG references two future cloud-managed artifacts:

1. `gs://.../pyspark/transform_matches.py`, the stable PySpark script
   that Composer can access without seeing a laptop.
2. Cloud Run Job `lol-dbt-build`, the isolated dbt runner.

The next implementation step creates and deploys those two artifacts. Until
then, use the safe mode above; `run_real_work=true` is intentionally not ready.
