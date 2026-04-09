###############################################################################
# Root Outputs
# Author: Christopher Amaral
###############################################################################

# --- Compute ----------------------------------------------------------------
output "ec2_instance_id" {
  description = "ID da instancia EC2 do cluster K8s"
  value       = module.compute.instance_id
}

output "ec2_public_ip" {
  description = "IP publico da instancia EC2"
  value       = module.compute.public_ip
}

output "ec2_public_dns" {
  description = "DNS publico da instancia EC2"
  value       = module.compute.public_dns
}

output "ssh_private_key" {
  description = "Chave SSH privada (somente se auto-gerada)"
  value       = module.compute.ssh_private_key
  sensitive   = true
}

# --- Networking -------------------------------------------------------------
output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}

# --- IAM / CI ---------------------------------------------------------------
output "github_actions_role_arn" {
  description = "ARN da IAM Role para GitHub Actions (OIDC)"
  value       = module.iam.github_actions_role_arn
}

# --- Storage ----------------------------------------------------------------
output "tfstate_bucket_name" {
  description = "Nome do bucket S3 do Terraform state"
  value       = module.storage.s3_bucket_name
}

output "tfstate_lock_table" {
  description = "Nome da tabela DynamoDB de lock"
  value       = module.storage.dynamodb_table_name
}
