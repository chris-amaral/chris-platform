output "ec2_instance_profile_name" {
  description = "Nome do Instance Profile para a EC2"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_role_arn" {
  description = "ARN da IAM Role da EC2"
  value       = aws_iam_role.ec2_instance.arn
}

output "github_actions_role_arn" {
  description = "ARN da IAM Role para GitHub Actions (OIDC)"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider do GitHub"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
