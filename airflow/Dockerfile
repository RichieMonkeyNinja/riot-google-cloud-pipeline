# This is intentionally a separate environment from the extractor and dbt.
# Airflow controls its own tightly-coupled dependency set; uv locks it here.
FROM ghcr.io/astral-sh/uv:0.5.24 AS uv

FROM python:3.11-slim-bookworm

COPY --from=uv /uv /uvx /bin/

ENV AIRFLOW_HOME=/opt/airflow \
    PATH=/opt/airflow/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

RUN groupadd --gid 50000 airflow \
    && useradd --uid 50000 --gid 50000 --create-home --home-dir /opt/airflow airflow

WORKDIR /opt/airflow
COPY airflow/pyproject.toml airflow/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project \
    && chown -R airflow:airflow /opt/airflow

USER airflow
