output "frontend_url" {
  description = "URL of the chat frontend"
  value       = module.frontend.cloudfront_domain_name
}

output "api_url" {
  description = "URL of the inference API (ALB)"
  value       = module.alb.alb_dns_name
}

// Consumed by deploy.sh and passed to build_and_push.sh, so Terraform stays the
// single source of truth for the repository name, account and region.
output "ecr_repository_url" {
  description = "ECR repository URL that the build script pushes images to"
  value       = module.ecr.repository_url
}

output "public_api_key" {
  description = "User-facing API key for authenticating requests"
  value       = var.public_api_key
  sensitive   = true
}