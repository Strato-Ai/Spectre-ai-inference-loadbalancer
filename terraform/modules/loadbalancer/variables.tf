# terraform/modules/loadbalancer/variables.tf
variable "project_name" {
  type    = string
  default = "spectre"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ami_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "admin_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed SSH access to the LB"
}

variable "backend_private_ips" {
  type        = list(string)
  description = "Backend private IPs for NGINX upstream config"
}

variable "tags" {
  type    = map(string)
  default = {}
}
