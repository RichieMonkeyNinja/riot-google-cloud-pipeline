# dbt environment

This is a separate `uv` project because `dbt-bigquery` has Google-library
version requirements that conflict with the ingestion project's newer Google
Cloud client libraries. Both projects remain reproducible because each has its
own `pyproject.toml` and `uv.lock`.

From this directory, install the locked dbt environment and create the dbt
project:

```bash
uv sync
uv run dbt init lol_analytics
```

When prompted, choose BigQuery with gcloud OAuth, project `self-learn-spark`,
dataset `lol_analytics`, and location `us-east1`. dbt initially writes the
local connection profile to `~/.dbt/profiles.yml`; copy the safe template in
the generated project to a project-specific `profiles.yml` instead. Do not
commit either profile or a service-account key.

After the interactive setup completes:

```bash
cd lol_analytics
cp profiles.yml.example profiles.yml
# Edit profiles.yml and replace YOUR_GCP_PROJECT_ID.
DBT_PROFILES_DIR=. uv run --project .. dbt debug
```
