# terraform/modules/loadbalancer/main.tf
resource "aws_security_group" "lb" {
  name_prefix = "${var.project_name}-lb-"
  vpc_id      = var.vpc_id

  # HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP redirect
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from admin CIDRs
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-lb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "lb" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.lb.id]
  key_name               = var.key_name
  private_ip             = "10.0.1.5"

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    backend_ips = var.backend_private_ips
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-lb"
    Role = "loadbalancer"
  })
}

resource "aws_eip" "lb" {
  instance = aws_instance.lb.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.project_name}-lb-eip" })
}
