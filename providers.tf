provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
      Deployment  = "consumer-asg"
    }
  }

  # Dynamic credentials via HCP Terraform variable set
  # TFC_AWS_PROVIDER_AUTH = true (configured in variable set agent_AWS_Dynamic_Creds)
  # TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::ACCOUNT:role/terraform (configured in variable set)
}
