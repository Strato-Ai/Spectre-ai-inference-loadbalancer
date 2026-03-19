# terraform/modules/client/main.tf
resource "aws_security_group" "client" {
  name_prefix = "${var.project_name}-client-"
  vpc_id      = var.vpc_id

  # SSH from LB
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.lb_security_group_id]
  }

  # Outbound to LB
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-client-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "client" {
  count                  = var.client_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.client.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    client_id = count.index + 1
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-client-${count.index + 1}"
    Role = "client"
  })
}
