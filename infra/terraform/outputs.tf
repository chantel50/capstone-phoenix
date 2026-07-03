output "master_public_ip" {
  description = "Public IP of k3s master node"
  value       = module.compute.master_public_ip
}

output "worker_public_ips" {
  description = "Public IPs of k3s worker nodes"
  value       = module.compute.worker_public_ips
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig from master"
  value       = "ssh -i ~/.ssh/phoenix-key ubuntu@${module.compute.master_public_ip}"
}