"""Orchestrate the League of Legends batch pipeline.

The default run is deliberately safe: it validates Airflow wiring and skips
all cloud work. Pass {"run_real_work": true} only when a real GCP rerun is
intended.
"""

from __future__ import annotations

import os
from datetime import datetime

from airflow import DAG
from airflow.exceptions import AirflowSkipException
from airflow.models.param import Param
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.cloud_run import CloudRunExecuteJobOperator
from airflow.providers.google.cloud.operators.dataproc import DataprocCreateBatchOperator
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
REGION = os.environ["GCP_REGION"]
RAW_BUCKET = os.environ["RAW_BUCKET"]
CURATED_BUCKET = os.environ["CURATED_BUCKET"]
DATAPROC_STAGING_BUCKET = os.environ["DATAPROC_STAGING_BUCKET"]
PIPELINE_ARTIFACTS_BUCKET = os.environ["PIPELINE_ARTIFACTS_BUCKET"]
PIPELINE_SERVICE_ACCOUNT = os.environ["PIPELINE_SERVICE_ACCOUNT"]
BQ_DATASET = os.environ["BQ_DATASET"]
INGESTION_JOB_NAME = os.environ["INGESTION_JOB_NAME"]
DBT_JOB_NAME = os.environ["DBT_JOB_NAME"]


def require_real_work(**context: object) -> None:
    """Prevent accidental cloud execution from the local UI or CLI."""
    dag_run = context["dag_run"]
    if not dag_run.conf.get("run_real_work", False):
        raise AirflowSkipException(
            "Safe demo mode: all GCP tasks skipped. Trigger with run_real_work=true to execute."
        )


DATAPROC_BATCH = {
    "pyspark_batch": {
        "main_python_file_uri": (
            f"gs://{PIPELINE_ARTIFACTS_BUCKET}/pyspark/transform_matches.py"
        ),
        "args": [
            f"--input=gs://{RAW_BUCKET}/matches/",
            f"--output=gs://{CURATED_BUCKET}/silver",
            "--mode=overwrite",
        ],
    },
    "environment_config": {
        "execution_config": {
            "service_account": PIPELINE_SERVICE_ACCOUNT,
            "staging_bucket": DATAPROC_STAGING_BUCKET,
            "ttl": "1200s",
        }
    },
}

with DAG(
    dag_id="lol_end_to_end",
    description="Cloud Run → Dataproc → BigQuery → dbt Cloud Run",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    params={"run_real_work": Param(False, type="boolean")},
    tags=["lol", "portfolio", "gcp"],
) as dag:
    safety_gate = PythonOperator(task_id="require_explicit_real_run", python_callable=require_real_work)

    ingest_raw = CloudRunExecuteJobOperator(
        task_id="ingest_raw",
        project_id=PROJECT_ID,
        region=REGION,
        job_name=INGESTION_JOB_NAME,
        deferrable=False,
    )

    bronze_to_silver = DataprocCreateBatchOperator(
        task_id="bronze_to_silver",
        project_id=PROJECT_ID,
        region=REGION,
        batch=DATAPROC_BATCH,
        batch_id="lol-bronze-to-silver-{{ ts_nodash | lower }}",
        deferrable=False,
    )

    load_silver_matches = GCSToBigQueryOperator(
        task_id="load_silver_matches",
        bucket=CURATED_BUCKET,
        source_objects=["silver/silver_matches/*/*.parquet"],
        destination_project_dataset_table=f"{PROJECT_ID}.{BQ_DATASET}.silver_matches",
        source_format="PARQUET",
        autodetect=True,
        create_disposition="CREATE_IF_NEEDED",
        write_disposition="WRITE_TRUNCATE",
    )

    load_silver_participants = GCSToBigQueryOperator(
        task_id="load_silver_participants",
        bucket=CURATED_BUCKET,
        source_objects=["silver/silver_participants/*/*.parquet"],
        destination_project_dataset_table=f"{PROJECT_ID}.{BQ_DATASET}.silver_participants",
        source_format="PARQUET",
        autodetect=True,
        create_disposition="CREATE_IF_NEEDED",
        write_disposition="WRITE_TRUNCATE",
    )

    dbt_build_gold = CloudRunExecuteJobOperator(
        task_id="dbt_build_gold",
        project_id=PROJECT_ID,
        region=REGION,
        job_name=DBT_JOB_NAME,
        deferrable=False,
    )

    safety_gate >> ingest_raw >> bronze_to_silver
    bronze_to_silver >> [load_silver_matches, load_silver_participants] >> dbt_build_gold
