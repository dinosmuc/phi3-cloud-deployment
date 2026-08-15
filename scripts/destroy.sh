#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

echo "  Gemma 4 Cloud Deployment — Destroy"
echo ""
echo "  WARNING: This will destroy ALL infrastructure"
echo "  and delete all resources in AWS."
echo ""
echo "  The Terraform state bucket is not touched — it is created outside"
echo "  the stack and has to be deleted manually if you no longer need it."
echo ""
read -p "  Are you sure? Type 'yes' to confirm: " confirm
echo ""

if [ "$confirm" != "yes" ]; then
    echo "  Cancelled. Nothing was destroyed."
    exit 0
fi

# The backend is a partial configuration, so a fresh clone has to be pointed at
# the state bucket before anything can be destroyed. backend.hcl is written by
# deploy.sh; if it is already initialised this is a no-op.
if [ -f backend.hcl ]; then
    terraform init -backend-config=backend.hcl
    echo ""
fi

echo "→ Destroying infrastructure..."
terraform destroy -auto-approve
echo ""
echo "  All resources destroyed."
