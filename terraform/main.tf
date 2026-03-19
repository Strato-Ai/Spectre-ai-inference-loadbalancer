# terraform/main.tf
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# WARNING: tls_private_key stores the private key in Terraform state in plaintext.
# For production, generate keys externally (ssh-keygen) and import only the public key.
# This approach is acceptable for dev/testing only.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "spectre" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0400"
}

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  tags         = local.common_tags
}

module "backend" {
  source = "./modules/backend"

  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  private_subnet_id    = module.network.private_subnet_id
  instance_type        = local.backend_instance_type
  ami_id               = local.ami_id
  key_name             = aws_key_pair.spectre.key_name
  lb_security_group_id = module.loadbalancer.security_group_id
  tags                 = local.common_tags
}

module "loadbalancer" {
  source = "./modules/loadbalancer"

  project_name        = var.project_name
  vpc_id              = module.network.vpc_id
  public_subnet_id    = module.network.public_subnet_id
  instance_type       = local.lb_instance_type
  ami_id              = local.ami_id
  key_name            = aws_key_pair.spectre.key_name
  admin_cidr_blocks   = var.admin_cidr_blocks
  backend_private_ips = module.backend.private_ips
  tags                = local.common_tags
}

module "client" {
  source = "./modules/client"

  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  public_subnet_id     = module.network.public_subnet_id
  instance_type        = local.client_instance_type
  ami_id               = local.ami_id
  key_name             = aws_key_pair.spectre.key_name
  lb_security_group_id = module.loadbalancer.security_group_id
  client_count         = var.client_count
  tags                 = local.common_tags
}
