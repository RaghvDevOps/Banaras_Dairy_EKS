# Secrets are NEVER hardcoded here. Provide values via:
#   1. Environment variables: export TF_VAR_db_password="..."
#   2. A gitignored secrets.auto.tfvars file (see secrets.auto.tfvars.example)

variable "db_password" {
  description = "Password for the Postgres app user (banaras_app). POC-grade — rotate before any real use."
  type        = string
  sensitive   = true
}

variable "ghcr_username" {
  description = "GitHub username used to pull private images from GHCR."
  type        = string
  sensitive   = true
}

variable "ghcr_token" {
  description = "GitHub Personal Access Token (read:packages scope) for pulling private GHCR images."
  type        = string
  sensitive   = true
}
