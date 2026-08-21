# Build stage: copy a pinned uv binary into the smaller Python runtime image.
FROM ghcr.io/astral-sh/uv:0.11.24 AS uv

# Runtime stage: this is the portable Linux box that Cloud Run will execute.
FROM python:3.11.15-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

COPY --from=uv /uv /uvx /bin/

WORKDIR /app

# Copy dependency files first. Docker can reuse this expensive layer when only
# application code changes.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# The image contains only the ingestion entrypoint, not local credentials,
# Terraform state, test data, or the PySpark transformation source.
COPY src/extract_gold_matches.py src/extract_gold_matches.py

ENTRYPOINT ["python", "src/extract_gold_matches.py"]
