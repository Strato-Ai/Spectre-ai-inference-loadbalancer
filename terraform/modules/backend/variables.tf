# terraform/modules/backend/variables.tf
variable "project_name" {
  type    = string
  default = "spectre"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.large"
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

variable "model_assignments" {
  type = list(object({
    ip    = string
    model = string
  }))
  default = [
    { ip = "10.0.2.10", model = "qwen3:4b" },
    { ip = "10.0.2.11", model = "llama3.1:8b" },
    { ip = "10.0.2.12", model = "deepseek-r1:7b" },
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
