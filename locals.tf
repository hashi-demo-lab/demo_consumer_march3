locals {
  # Naming prefix pattern: {project}-{environment}
  naming_prefix = "${var.project_name}-${var.environment}"

  # Availability zones for ap-southeast-2 region
  availability_zones = [
    "ap-southeast-2a",
    "ap-southeast-2b"
  ]

  # Common tags applied to resources (supplements provider default_tags)
  common_tags = {
    Terraform = "true"
    Region    = var.aws_region
  }
}
