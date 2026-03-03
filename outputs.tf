output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer for accessing the application"
  value       = module.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer for CloudWatch metrics and logging configuration"
  value       = module.alb.arn
}

output "alb_zone_id" {
  description = "Route53 hosted zone ID of the ALB for DNS alias record creation"
  value       = module.alb.zone_id
}

output "asg_id" {
  description = "Auto Scaling Group identifier for AWS console reference"
  value       = module.autoscaling.autoscaling_group_id
}

output "asg_name" {
  description = "Auto Scaling Group name for CloudWatch metrics and API operations"
  value       = module.autoscaling.autoscaling_group_name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group for IAM policy attachments and monitoring"
  value       = module.autoscaling.autoscaling_group_arn
}

output "launch_template_id" {
  description = "Launch template identifier for AMI update workflows"
  value       = module.autoscaling.launch_template_id
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
  value       = aws_security_group.asg_instances.id
}
