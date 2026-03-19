# terraform/modules/client/outputs.tf
output "public_ips" {
  value = aws_instance.client[*].public_ip
}

output "private_ips" {
  value = aws_instance.client[*].private_ip
}
