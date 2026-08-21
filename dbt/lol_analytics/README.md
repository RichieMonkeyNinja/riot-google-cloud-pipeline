# League of Legends gold analytics

This dbt project converts the PySpark-created silver table into analyst-ready
gold tables in BigQuery.

## Before the first build

The PySpark job must have uploaded `silver_participants` to BigQuery first:

```bash
cd ../..
bash scripts/load_mock_to_gcp.sh
cd dbt/lol_analytics
```

## Local dbt profile

Create a project-specific profile from the safe template. This is configuration
only; OAuth credentials remain in gcloud's local Application Default
Credentials, not in the repository.

```bash
cp profiles.yml.example profiles.yml
# Edit profiles.yml and replace YOUR_GCP_PROJECT_ID.
```

Always use this local profile directory when running dbt:

```bash
DBT_PROFILES_DIR=. uv run --project .. dbt debug
```

## Build and test

Use the parent `dbt` uv environment; do not install dbt packages in this child
project:

```bash
DBT_PROFILES_DIR=. uv run --project .. dbt debug
DBT_PROFILES_DIR=. uv run --project .. dbt build
```

`dbt build` creates `gold_champion_performance`, then runs source and gold
tests. A failing dbt test means its SQL query returned bad rows.

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices
