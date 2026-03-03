output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer for accessing the application"
  value       = "" # TODO: wire to module.alb.dns_name in Item B (ALB module)
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer for CloudWatch metrics and logging configuration"
  value       = "" # TODO: wire to module.alb.arn in Item B (ALB module)
}

output "alb_zone_id" {
  description = "Route53 hosted zone ID of the ALB for DNS alias record creation"
  value       = "" # TODO: wire to module.alb.zone_id in Item B (ALB module)
}

output "asg_id" {
  description = "Auto Scaling Group identifier for AWS console reference"
  value       = "" # TODO: wire to module.autoscaling.autoscaling_group_id in Item C (ASG module)
}

output "asg_name" {
  description = "Auto Scaling Group name for CloudWatch metrics and API operations"
  value       = "" # TODO: wire to module.autoscaling.autoscaling_group_name in Item C (ASG module)
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group for IAM policy attachments and monitoring"
  value       = "" # TODO: wire to module.autoscaling.autoscaling_group_arn in Item C (ASG module)
}

output "launch_template_id" {
  description = "Launch template identifier for AMI update workflows"
  value       = "" # TODO: wire to module.autoscaling.launch_template_id in Item C (ASG module)
}

output "vpc_id" {
  description = "VPC ID used for deployment for networking context"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "Subnet IDs used for ALB and ASG placement"
  value       = data.aws_subnets.default.ids
}

output "asg_security_group_id" {
  description = "Security group ID for ASG instances for manual rule additions"
  value       = "" # TODO: wire to aws_security_group.asg_instances.id in Item D (Security groups)
}
