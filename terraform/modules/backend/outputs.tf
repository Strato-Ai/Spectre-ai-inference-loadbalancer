# terraform/modules/backend/outputs.tf
output "private_ips" {
  value = aws_instance.backend[*].private_ip
}

output "security_group_id" {
  value = aws_security_group.backend.id
}
