# GCP Self-Learning Project

## Purpose

This project teaches a beginner how a small data-engineering pipeline is built on
Google Cloud Platform (GCP). The goal is learning the tools and the reasoning
behind them; the League of Legends data is only the example dataset.

## Learning approach

- Use Infrastructure as Code (IaC) with Terraform for cloud resources.
- Use `uv` as the only Python dependency and virtual-environment manager. Add
  packages with `uv add`, run tools with `uv run`, and commit `uv.lock`.
- Use Ubuntu on WSL 2 as the local development environment. Run all project
  commands through its Bash terminal, even if the repository remains on the
  Windows drive under `/mnt/c/...`.
- Prefer Python/PySpark for transformations, Google Cloud Storage (GCS) for
  files, and BigQuery for analytics.
- Explain unfamiliar terms in plain language before using them.
- Work in small, verifiable steps. State what a command changes, how to run it,
  and how to confirm it worked.
- Ask for confirmation when a design choice is uncertain or would materially
  affect cost, security, or scope.
- Occasionally check understanding with one short question. Explain the answer
  if it is not clear.
- Suggest another tool only when it makes the lesson simpler, safer, or more
  appropriate, and explain the trade-off.
- For every future task, proactively suggest a more reproducible or
  industry-standard alternative when one exists. Explain the practical
  trade-off in beginner-friendly language (for example, pytest instead of
  unittest when its fixtures and failure output improve the project).
- Before making a materially different architecture, tool, or workflow choice,
  ask the learner for confirmation. Prefer approaches that another student can
  reproduce from a clean clone without sharing secrets or relying on personal
  machine state.

## Safety and credentials

- Never commit, paste, or hard-code API keys, service-account keys, passwords,
  or Terraform state containing secrets.
- Ask for the minimum required access only when the learner reaches that step.
- Prefer local authenticated tooling (`gcloud auth application-default login`)
  and Secret Manager over downloaded credential files.
- Before creating chargeable GCP resources, explain the expected cost drivers
  and give the learner a chance to confirm.

## Scope

The initial pipeline may choose modest, public Riot API data and simple useful
transformations. It should still demonstrate the full flow: ingest, store raw
data, transform it, load/query it, and clean up resources afterward.
