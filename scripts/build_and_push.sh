#!/bin/bash
set -euo pipefail

# The full ECR repository URL is passed in by deploy.sh, which reads it from the
# Terraform output. Nothing about the account, region or repository name is
# redefined here, so this script and Terraform cannot drift apart.
#
# Usage: build_and_push.sh <account>.dkr.ecr.<region>.amazonaws.com/<repository>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <ecr-repository-url>"
    echo "Hint:  cd terraform && terraform output -raw ecr_repository_url"
    exit 1
fi

# Resolve paths relative to the repo root, so this works no matter the caller's
# working directory (run directly from the repo root, or invoked by deploy.sh
# which runs from terraform/). The docker build contexts below are repo-relative.
cd "$(dirname "$0")/.."

REPO_URL="$1"
REGISTRY="${REPO_URL%%/*}"
REGION=$(echo "$REGISTRY" | cut -d. -f4)

# HuggingFace token for downloading the model at image-build time. Required if the
# model repo is gated; harmless (empty) if it is ungated. Export HF_TOKEN before running.
HF_TOKEN="${HF_TOKEN:-}"

echo "Registry: ${REGISTRY}"
echo "Region:   ${REGION}"
echo "Repo:     ${REPO_URL}"
echo ""

# Authenticate Docker to ECR
echo "→ Authenticating Docker to ECR..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${REGISTRY}"
echo ""

# Build vLLM image (this downloads the model — takes 10-15 min first time)
echo "→ Building vLLM image (this may take a while)..."
docker build --provenance=false --sbom=false --build-arg HF_TOKEN="${HF_TOKEN}" -t "${REPO_URL}:vllm" containers/vllm/
echo ""

# Build proxy (auth-proxy sidecar) image
echo "→ Building proxy image..."
docker build --provenance=false --sbom=false -t "${REPO_URL}:proxy" containers/proxy/
echo ""

# Push vLLM image
echo "→ Pushing vLLM image to ECR..."
docker push "${REPO_URL}:vllm"
echo ""

# Push proxy image
echo "→ Pushing proxy image to ECR..."
docker push "${REPO_URL}:proxy"
echo ""

echo "  Done! Images pushed to ECR:"
echo "  vLLM:   ${REPO_URL}:vllm"
echo "  proxy:  ${REPO_URL}:proxy"
