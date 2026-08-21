# dbt has its own small, locked runtime. Do not combine it with PySpark or the
# Riot extractor: each job has different dependencies and deployment cadence.
FROM ghcr.io/astral-sh/uv:0.11.24 AS uv

FROM python:3.11.15-slim-bookworm

COPY --from=uv /uv /uvx /bin/

ENV PATH=/app/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

WORKDIR /app
COPY dbt/pyproject.toml dbt/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# Copy only reviewed project files. The local profiles.yml is ignored by
# Docker; the credential-free Cloud Run profile is renamed at build time.
COPY dbt/lol_analytics/dbt_project.yml ./dbt_project.yml
COPY dbt/lol_analytics/models ./models
COPY dbt/lol_analytics/tests ./tests
COPY dbt/lol_analytics/macros ./macros
COPY dbt/lol_analytics/analyses ./analyses
COPY dbt/lol_analytics/seeds ./seeds
COPY dbt/lol_analytics/snapshots ./snapshots
COPY dbt/lol_analytics/profiles.cloud-run.yml ./profiles.yml

CMD ["dbt", "build", "--project-dir", "/app", "--profiles-dir", "/app", "--target", "cloud_run"]
