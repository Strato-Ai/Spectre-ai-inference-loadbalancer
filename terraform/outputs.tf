# terraform/outputs.tf
output "lb_public_ip" {
  value       = module.loadbalancer.public_ip
  description = "Load balancer public IP"
}

output "backend_private_ips" {
  value       = module.backend.private_ips
  description = "Backend private IPs"
}

output "client_public_ips" {
  value       = module.client.public_ips
  description = "Client public IPs"
}

output "ssh_key_path" {
  value       = local_sensitive_file.ssh_key.filename
  description = "Path to SSH private key"
  sensitive   = true
}

output "instance_tier" {
  value       = var.instance_tier
  description = "Active instance tier"
}
