# terraform/variables.tf
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "spectre"
}

variable "instance_tier" {
  type        = string
  default     = "testing"
  description = "Instance sizing tier: testing (all t3.small), cpu (backends t3.large), gpu (backends g4dn.xlarge)"
  validation {
    condition     = contains(["testing", "cpu", "gpu"], var.instance_tier)
    error_message = "instance_tier must be one of: testing, cpu, gpu."
  }
}

variable "client_count" {
  type    = number
  default = 2
  validation {
    condition     = var.client_count >= 1 && var.client_count <= 4
    error_message = "client_count must be between 1 and 4."
  }
}

variable "admin_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed SSH access to the LB"
}

locals {
  backend_instance_type = {
    testing = "t3.small"
    cpu     = "t3.large"
    gpu     = "g4dn.xlarge"
  }[var.instance_tier]

  lb_instance_type = "t3.small"

  client_instance_type = "t3.small"

  # Ubuntu 24.04 LTS AMI (us-east-1) — update as needed
  ami_id = "ami-0a0e5d9c7acc336f1"

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Environment = var.instance_tier
  }
}
