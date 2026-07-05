terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0.0"

  # Partial backend config on purpose: bucket/table names are AWS-account-
  # specific, so they live in a gitignored backend.hcl (see backend.hcl.example)
  # instead of being hardcoded here. Run: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = "ap-south-1"
}