# terraform/modules/backend/main.tf
resource "aws_security_group" "backend" {
  name_prefix = "${var.project_name}-backend-"
  vpc_id      = var.vpc_id

  # Inference API from LB only
  ingress {
    from_port       = 1234
    to_port         = 1234
    protocol        = "tcp"
    security_groups = [var.lb_security_group_id]
  }

  # GPU metrics from LB only
  ingress {
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.lb_security_group_id]
  }

  # SSH from LB only (bastion)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.lb_security_group_id]
  }

  # Outbound for package installs and model downloads
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-backend-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "backend" {
  count                  = length(var.model_assignments)
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = var.key_name
  private_ip             = var.model_assignments[count.index].ip

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    model_name = var.model_assignments[count.index].model
    backend_id = count.index + 1
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name  = "${var.project_name}-backend-${count.index + 1}"
    Role  = "backend"
    Model = var.model_assignments[count.index].model
  })
}
