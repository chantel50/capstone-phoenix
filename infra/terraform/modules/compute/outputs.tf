output "master_public_ip" {
  description = "Public IP of k3s master node"
  value       = aws_instance.k3s_master.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of k3s worker nodes"
  value       = aws_instance.k3s_worker[*].public_ip
}

output "master_private_ip" {
  description = "Private IP of k3s master node"
  value       = aws_instance.k3s_master.private_ip
}