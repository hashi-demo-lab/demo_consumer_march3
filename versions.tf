terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.19"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  cloud {
    organization = "hashi-demos-apj"
    workspaces {
      name = "sandbox_consumer_asg_workspace"
    }
  }
}
