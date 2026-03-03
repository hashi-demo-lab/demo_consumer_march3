variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be valid AWS region format (e.g., ap-southeast-2, us-east-1)"
  }
}

variable "project_name" {
  description = "Project identifier for resource naming and tagging"
  type        = string
  default     = "consumer-asg"
}

variable "environment" {
  description = "Environment name for resource tagging and configuration"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Must be one of: development, staging, production"
  }
}

variable "owner" {
  description = "Owner email or team identifier for resource accountability"
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "Owner must be a non-empty string"
  }
}

variable "instance_type" {
  description = "EC2 instance type for ASG launch template"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.", var.instance_type))
    error_message = "Must match t3.* or t2.* pattern (e.g., t3.micro, t2.small)"
  }
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in Auto Scaling Group"
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 0
    error_message = "Must be >= 0"
  }
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in Auto Scaling Group"
  type        = number
  default     = 3

  validation {
    condition     = var.asg_max_size >= 1 && var.asg_max_size <= 10
    error_message = "Must be >= 1 and <= 10"
  }
}

variable "asg_desired_capacity" {
  description = "Initial desired number of EC2 instances in Auto Scaling Group"
  type        = number
  default     = 1

  validation {
    condition     = var.asg_desired_capacity >= 0
    error_message = "Must be >= 0"
  }
}

variable "asg_health_check_grace_period" {
  description = "Time in seconds after instance launch before health checks start"
  type        = number
  default     = 300

  validation {
    condition     = var.asg_health_check_grace_period >= 0
    error_message = "Must be >= 0"
  }
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling policy"
  type        = number
  default     = 70.0

  validation {
    condition     = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "Must be > 0 and <= 100"
  }
}

variable "alb_health_check_path" {
  description = "HTTP path for ALB target group health checks"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/", var.alb_health_check_path))
    error_message = "Must start with /"
  }
}

variable "alb_health_check_interval" {
  description = "Time in seconds between ALB health checks"
  type        = number
  default     = 30

  validation {
    condition     = var.alb_health_check_interval >= 5 && var.alb_health_check_interval <= 300
    error_message = "Must be >= 5 and <= 300"
  }
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization percentage threshold for CloudWatch alarm"
  type        = number
  default     = 80.0

  validation {
    condition     = var.alarm_cpu_threshold > 0 && var.alarm_cpu_threshold <= 100
    error_message = "Must be > 0 and <= 100"
  }
}

variable "alarm_response_time_threshold" {
  description = "ALB target response time in seconds threshold for CloudWatch alarm"
  type        = number
  default     = 1.0

  validation {
    condition     = var.alarm_response_time_threshold > 0
    error_message = "Must be > 0"
  }
}
