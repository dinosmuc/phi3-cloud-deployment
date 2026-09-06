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

# HuggingFace token for downloading the model at image-build time. The Gemma repo is
# gated, so this is required. It is handed to the build as a BuildKit secret rather
# than a build argument, which would persist in the image history.
if [ -z "${HF_TOKEN:-}" ]; then
    echo "  HF_TOKEN is not set. Accept the Gemma licence on Hugging Face, then:"
    echo "  export HF_TOKEN=hf_..."
    exit 1
fi
export HF_TOKEN

# Both builds below need BuildKit: --provenance/--sbom are Buildx flags, and the vLLM
# Dockerfile mounts the token with RUN --mount=type=secret. `docker build` only routes
# to Buildx from Docker Engine 23.0, and an inherited DOCKER_BUILDKIT=0 would opt back
# out of it, so pin it on rather than trusting the environment.
if ! docker buildx version >/dev/null 2>&1; then
    echo "  docker buildx is missing. This build needs BuildKit (Docker >= 23)."
    echo "  Install the docker-buildx-plugin package, then re-run."
    exit 1
fi
export DOCKER_BUILDKIT=1

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
docker build --provenance=false --sbom=false \
    --platform=linux/amd64 \
    --secret id=HF_TOKEN,env=HF_TOKEN \
    -t "${REPO_URL}:vllm" containers/vllm/
echo ""

# Build proxy (auth-proxy sidecar) image
echo "→ Building proxy image..."
# ECS runs these on a g6.xlarge, which is x86_64. Without --platform, Docker builds for
# the builder's own architecture, so an Apple Silicon or other ARM machine would push
# arm64 images that fail on the instance with "exec format error". Building amd64 on an
# ARM host goes through emulation and is slower, which is the right trade against an
# image that cannot run at all.
docker build --provenance=false --sbom=false \
    --platform=linux/amd64 \
    -t "${REPO_URL}:proxy" containers/proxy/
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
