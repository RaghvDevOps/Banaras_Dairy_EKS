# Secrets live in SSM Parameter Store (free tier: up to 10,000 Standard
# parameters, no cost) instead of AWS Secrets Manager (~$0.40/secret/month) --
# a deliberate cost trade-off for a POC/portfolio project. Values are
# encrypted at rest using the AWS-managed KMS key (also free).
#
# scripts/deploy.sh reads these back with `aws ssm get-parameter
# --with-decryption` at deploy time, and creates the actual Kubernetes
# Secret objects from them. Nothing sensitive ever gets committed to git,
# and nothing sensitive lives inside the Kubernetes manifests themselves.

resource "aws_ssm_parameter" "db_password" {
  name        = "/banaras-dairy-eks/db_password"
  description = "Postgres app user (banaras_app) password"
  type        = "SecureString"
  value       = var.db_password
}

resource "aws_ssm_parameter" "ghcr_username" {
  name        = "/banaras-dairy-eks/ghcr_username"
  description = "GitHub username for GHCR image pulls"
  type        = "SecureString"
  value       = var.ghcr_username
}

resource "aws_ssm_parameter" "ghcr_token" {
  name        = "/banaras-dairy-eks/ghcr_token"
  description = "GitHub PAT (read:packages) for GHCR image pulls"
  type        = "SecureString"
  value       = var.ghcr_token
}
