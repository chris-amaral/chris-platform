output "k8s_node_sg_id" {
  description = "ID do Security Group da instancia K8s"
  value       = aws_security_group.k8s_node.id
}

output "k8s_node_sg_name" {
  description = "Nome do Security Group da instancia K8s"
  value       = aws_security_group.k8s_node.name
}
