# terraform/modules/client/variables.tf
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

variable "lb_security_group_id" {
  type = string
}

variable "client_count" {
  type    = number
  default = 2
  validation {
    condition     = var.client_count >= 1 && var.client_count <= 4
    error_message = "client_count must be between 1 and 4."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
