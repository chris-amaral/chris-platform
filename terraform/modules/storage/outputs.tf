output "s3_bucket_name" {
  description = "Nome do bucket S3 para o state do Terraform"
  value       = aws_s3_bucket.tfstate.id
}

output "s3_bucket_arn" {
  description = "ARN do bucket S3"
  value       = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para lock do state"
  value       = aws_dynamodb_table.tfstate_lock.name
}
