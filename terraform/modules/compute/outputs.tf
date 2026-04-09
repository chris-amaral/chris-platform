output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.k8s_node.id
}

output "public_ip" {
  description = "IP publico da instancia EC2"
  value       = aws_instance.k8s_node.public_ip
}

output "public_dns" {
  description = "DNS publico da instancia EC2"
  value       = aws_instance.k8s_node.public_dns
}

output "private_ip" {
  description = "IP privado da instancia EC2"
  value       = aws_instance.k8s_node.private_ip
}

output "ssh_private_key" {
  description = "Chave SSH privada (somente quando auto-gerada)"
  value       = var.key_name == "" ? tls_private_key.generated[0].private_key_openssh : null
  sensitive   = true
}

output "ssh_key_name" {
  description = "Nome do key pair SSH utilizado"
  value       = local.key_name
}

output "ami_id" {
  description = "ID da AMI utilizada"
  value       = data.aws_ami.ubuntu.id
}
