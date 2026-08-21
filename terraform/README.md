# Terraform infrastructure

This folder creates the first learning-pipeline infrastructure in an existing,
billed GCP project:

- Google Cloud APIs required by the project.
- Private, versioned raw and curated GCS buckets.
- A regional BigQuery dataset.
- A service account for later pipeline jobs and its required roles.
- An **empty** Secret Manager secret container for the Riot API key.
- An optional Cloud Composer (managed Airflow) demo environment, disabled by
  default because it has an hourly cost while it exists.

It does not create a billing account, put a secret into Terraform state, submit
a Spark job, or delete data automatically.

## Folder map

Terraform reads every `.tf` file in this folder as one combined construction
plan. Splitting files changes readability only; it does not create separate
Terraform projects.

| File | Responsibility |
| --- | --- |
| `versions.tf` | Terraform and Google-provider versions, plus provider setup. |
| `variables.tf` | Inputs you choose: project ID, region, and environment. |
| `locals.tf` | Shared names and reusable lists of APIs and permissions. |
| `apis.tf` | Enables the required Google Cloud services. |
| `storage.tf` | Creates the raw and curated GCS buckets. |
| `bigquery.tf` | Creates the analytics dataset. |
| `iam.tf` | Creates the pipeline robot identity and grants its permissions. |
| `secret-manager.tf` | Creates the empty locked box for the Riot API key. |
| `composer.tf` | Optional, separately removable Cloud Composer demo and DAG upload. |
| `outputs.tf` | Prints useful resource names after a successful apply. |
| `terraform.tfvars` | Your private project-specific values; never commit it. |

## Before you run Terraform

In Ubuntu on WSL, make sure the active project is correct and that Application
Default Credentials exist:

```bash
gcloud config get-value project
gcloud auth application-default login --no-launch-browser
```

The project must already have billing enabled. `us-east1` is used by default;
it is the South Carolina region.

## Plan and apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and replace the project_id placeholder.
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Read the plan before confirming. The initial apply enables APIs and creates
storage, BigQuery, IAM, and Secret Manager resources. These can incur small
costs, especially once data and queries are added.

## Important safety rule

Never add the Riot API-key value to `.tf`, `.tfvars`, `terraform.tfstate`, or a
commit. Terraform creates only the secret container. We will add the value with
`gcloud secrets versions add` later, after you have a valid Riot API key.

## Cloud Composer demo: create, inspect, remove

Cloud Composer is Google-managed Airflow. Unlike Cloud Run Jobs, it keeps
servers running for its web UI and scheduler, so it costs money for every hour
the environment exists. The project therefore uses an explicit off switch.

Create the demo only when you are ready to inspect Airflow:

```bash
terraform apply -var='enable_composer_demo=true'
```

Creation commonly takes about 20--30 minutes. Terraform uploads
`airflow/dags/lol_end_to_end.py` to Composer automatically. The default DAG
run is safe: its first task skips all GCP work unless you explicitly pass
`{"run_real_work": true}`.

Open the UI after apply:

```bash
terraform output -raw composer_airflow_uri
```

When the demo is over, remove **only Composer** with this command. It leaves
raw data, BigQuery, Cloud Run, Artifact Registry, and the rest of the project
intact:

```bash
terraform apply -var='enable_composer_demo=false'
```

The Composer API remains enabled after removal. An enabled API alone does not
run Composer machines or incur Composer-environment charges.
