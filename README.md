# Phi-3 Cloud Deployment

Scalable LLM inference service on AWS using ECS, Terraform, and HuggingFace TGI.

Deploys Microsoft Phi-3 Mini 3.8B (AWQ 4-bit) as a streaming inference API with a real-time chat frontend. Responses are delivered token-by-token via Server-Sent Events.

## Architecture
```
Users ──→ CloudFront ──→ S3 (static frontend)
Users ──→ ALB ──→ ECS Task ──→ nginx (:80) ──→ TGI + Phi-3 (:8080, GPU)
```

- **Compute:** ECS on EC2 with g4dn.xlarge (NVIDIA T4, 16 GB VRAM)
- **Model:** Phi-3 Mini 3.8B AWQ quantised (~2.3 GB), pre-baked into Docker image
- **Serving:** HuggingFace TGI 3.x with continuous batching and SSE streaming
- **Networking:** Private subnets, VPC Endpoints (no NAT Gateway)
- **Scaling:** 0–3 instances via ECS Capacity Provider. Scales to zero when idle ($0 cost)
- **Security:** API key auth (nginx), WAF, HTTPS, private subnets
- **IaC:** Terraform with 6 modules (networking, ecr, alb, ecs, frontend, monitoring)

## Prerequisites

- AWS account with GPU quota (g4dn.xlarge requires `Running On-Demand G and VT instances` ≥ 4)
- AWS CLI configured (`aws configure`)
- Terraform ≥ 1.5
- Docker

## Quick Start
```bash
# 1. Clone
git clone https://github.com/dinosmuc/phi3-cloud-deployment.git
cd phi3-cloud-deployment

# 2. Configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars — set your api_key

# 3. Initialise Terraform
cd terraform
terraform init

# 4. Deploy ECR first
terraform apply -target=module.ecr

# 5. Build and push Docker images
cd ..
./scripts/build_and_push.sh

# 6. Deploy everything
cd terraform
terraform apply
```

Terraform outputs your `frontend_url`, `api_url`, and `api_key`.

## Usage

1. Open the `frontend_url` in a browser
2. Enter your API key
3. Type a message and see the response stream in real-time

**Note:** If the service has scaled to zero, the first request triggers a cold start (~3–5 minutes). The frontend retries automatically.

## Tear Down
```bash
cd terraform
terraform destroy
```

## Cost Estimate (eu-central-1)

| Scenario | Cost |
|----------|------|
| ~20 hours active testing (on-demand) | ~$17 |
| ~20 hours active testing (spot) | ~$9 |
| Idle (scaled to zero) | $0.00/hr |

## Project Structure
```
terraform/              Terraform IaC (6 modules)
├── modules/
│   ├── networking/     VPC, subnets, security groups, VPC endpoints
│   ├── ecr/            Docker image registry
│   ├── alb/            Load balancer, target group, WAF
│   ├── ecs/            Cluster, task definition, auto-scaling
│   ├── frontend/       S3 + CloudFront
│   └── monitoring/     CloudWatch dashboard and alarms
containers/
├── tgi/                TGI with pre-baked Phi-3 AWQ model
└── nginx/              Reverse proxy with API key auth and CORS
frontend/               Static chat UI (HTML/CSS/JS)
scripts/                Build, deploy, destroy, and test helpers
```

## License

MIT
