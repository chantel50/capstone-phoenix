output "security_group_id" {
  description = "ID of the k3s security group"
  value       = aws_security_group.k3s.id
}