#!/usr/bin/env bash
# Installs public development tools for this repository on Ubuntu in WSL 2.
# It never authenticates a GCP account and never reads or writes secrets.

set -euo pipefail

if [[ "$(. /etc/os-release && printf '%s' "$ID")" != "ubuntu" ]]; then
  echo "This bootstrap script supports Ubuntu only." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Installing Ubuntu prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common openjdk-17-jdk

if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Installing Google Cloud CLI..."
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/cloud.google.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y google-cloud-cli
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  . /etc/os-release
  ubuntu_codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${ubuntu_codename} main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y terraform
fi

cd "$repo_root"
uv python install 3.11
uv sync

echo
echo "Bootstrap complete. Verify with: uv --version && gcloud --version && terraform version && java -version"
echo "Next, after creating your billed GCP project: gcloud init"
