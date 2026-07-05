output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = "ap-south-1"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

# Non-secret DB constants -- single source of truth, so scripts/deploy.sh
# doesn't have to hardcode these separately from what postgres.yaml expects.
output "db_user" {
  value = "banaras_app"
}

output "db_name" {
  value = "banaras_dairy"
}

output "recovery_db_name" {
  value = "banaras_dairy_recovery"
}

output "ssm_db_password_path" {
  value = aws_ssm_parameter.db_password.name
}

output "ssm_ghcr_username_path" {
  value = aws_ssm_parameter.ghcr_username.name
}

output "ssm_ghcr_token_path" {
  value = aws_ssm_parameter.ghcr_token.name
}
