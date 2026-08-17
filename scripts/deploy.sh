#!/bin/bash
set -euo pipefail

echo "  Gemma 4 Cloud Deployment — Deploy"
echo ""

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform/terraform.tfvars"


# PREFLIGHT
# Fail early with a clear message instead of half-way through an apply.

echo "→ Preflight checks..."

for tool in terraform aws docker; do
    if ! command -v "$tool" >/dev/null; then
        echo "  Missing required tool: ${tool}. See the README for versions."
        exit 1
    fi
done

if [ ! -f "$TFVARS" ]; then
    echo "  Missing terraform/terraform.tfvars."
    echo "  Copy terraform/terraform.tfvars.example and fill in your values."
    exit 1
fi

if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    echo "  AWS credentials are not configured. Run 'aws configure' first."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "  Docker is installed but the daemon is not running."
    exit 1
fi

# Checked here as well as in build_and_push.sh, so a missing token fails before any
# AWS resources are created rather than 10 minutes into the image build.
if [ -z "${HF_TOKEN:-}" ]; then
    echo "  HF_TOKEN is not set. The Gemma model repo is gated — accept the licence"
    echo "  on Hugging Face, then: export HF_TOKEN=hf_..."
    exit 1
fi

# Read a setting from terraform.tfvars, falling back to the default in variables.tf.
# Only the two values needed to create the state bucket are read this way, because
# that has to happen before Terraform runs. Everything else comes from outputs.
tfvar() {
    local value
    value=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$TFVARS" | head -1 | cut -d'"' -f2 || true)
    echo "${value:-$2}"
}

PROJECT_NAME=$(tfvar project_name gemma-inference)
REGION=$(tfvar aws_region eu-central-1)
STATE_BUCKET="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"

echo "  Account:  ${ACCOUNT_ID}"
echo "  Region:   ${REGION}"
echo "  State:    s3://${STATE_BUCKET}"
echo ""


# STATE BUCKET
# Terraform cannot create its own backend, so it is bootstrapped here. The account
# ID makes the globally-unique bucket name collision-free in any AWS account.

echo "→ Checking the Terraform state bucket..."

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
    echo "  Already exists."
else
    echo "  Creating ${STATE_BUCKET}..."

    # us-east-1 rejects a LocationConstraint; every other region requires one.
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" >/dev/null
    else
        aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
    fi

    aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
        --versioning-configuration Status=Enabled

    aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

    aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    echo "  Created with versioning, encryption and public access blocked."
fi
echo ""

# Backend settings for this account. Written to disk so that plain terraform
# commands can be re-run by hand later with -backend-config=backend.hcl.
cat > "${REPO_ROOT}/terraform/backend.hcl" <<EOF
bucket = "${STATE_BUCKET}"
region = "${REGION}"
EOF

cd "${REPO_ROOT}/terraform"

echo "→ Initialising Terraform..."
terraform init -backend-config=backend.hcl
echo ""

# Step 1: ECR must exist before images can be pushed. A plain full apply would
# create the task definition referencing images that aren't in ECR yet, leaving
# the first request to fail with an image-pull error. So create ECR first.
echo "→ Step 1/3: Creating the ECR repository (terraform apply -target=module.ecr)..."
read -p "  Apply ECR repository? Type 'yes' to confirm: " confirm
echo ""
if [ "$confirm" != "yes" ]; then
    echo "  Cancelled. Nothing was applied."
    exit 0
fi
terraform apply -target=module.ecr -auto-approve
echo ""

# Step 2: build and push the vllm + proxy images into the now-existing repo.
# The repository URL comes straight from the Terraform output, so the build script
# can never push to a different repository or region than the one ECS reads from.
# Docker layer caching makes repeat runs fast (the model-download layer is reused
# unless the Dockerfile or HF_TOKEN changes), and ECR skips layers it already has.
echo "→ Step 2/3: Building and pushing container images..."
"${REPO_ROOT}/scripts/build_and_push.sh" "$(terraform output -raw ecr_repository_url)"
echo ""

# Step 3: apply the rest of the stack.
echo "→ Step 3/3: Planning the remaining infrastructure..."
terraform plan -out=tfplan
echo ""

read -p "  Apply these changes? Type 'yes' to confirm: " confirm
echo ""

if [ "$confirm" != "yes" ]; then
    rm -f tfplan
    echo "  Cancelled. ECR and images exist, but the rest of the stack was not applied."
    exit 0
fi

echo "→ Applying infrastructure..."
terraform apply tfplan
rm -f tfplan
echo ""

echo "  Deployment Complete!"
echo ""

terraform output
echo ""
echo "  The API key is hidden above. Print it with:"
echo "  cd terraform && terraform output -raw public_api_key"
