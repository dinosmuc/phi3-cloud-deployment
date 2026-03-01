output "frontend_url" {
  description = "URL of the chat frontend"
  value       = module.frontend.cloudfront_domain_name
}

output "api_url" {
  description = "URL of the inference API (ALB)"
  value       = module.alb.alb_dns_name
}

output "api_key" {
  description = "API key for authenticating requests"
  value       = var.api_key
  sensitive   = true
}