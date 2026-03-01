variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "phi3-inference"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for ECS GPU tasks"
  type        = string
  default     = "g4dn.xlarge"
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 3
}

variable "api_key" {
  description = "API key for authenticating requests to the inference endpoint"
  type        = string
  sensitive   = true
}