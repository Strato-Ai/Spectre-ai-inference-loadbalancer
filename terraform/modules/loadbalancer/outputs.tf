# terraform/modules/loadbalancer/outputs.tf
output "public_ip" {
  value = aws_eip.lb.public_ip
}

output "private_ip" {
  value = aws_instance.lb.private_ip
}

output "security_group_id" {
  value = aws_security_group.lb.id
}
