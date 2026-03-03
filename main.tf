# ============================================================================
# Application Load Balancer
# ============================================================================

module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  name    = "${local.naming_prefix}-alb"
  vpc_id  = data.aws_vpc.default.id
  subnets = data.aws_subnets.default.ids

  # Internet-facing ALB for development environment
  internal                   = false
  enable_deletion_protection = false # [SECURITY OVERRIDE] Development environment, deletion protection disabled for rapid iteration

  # Security hardening
  drop_invalid_header_fields = true

  # Security group rules for ALB
  security_group_rules = {
    ingress_http = {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTP traffic from internet"
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow all outbound traffic"
    }
  }

  # Target group configuration
  target_groups = {
    web = {
      name             = "${local.naming_prefix}-web-tg"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      vpc_id           = data.aws_vpc.default.id

      health_check = {
        enabled             = true
        path                = var.alb_health_check_path
        interval            = var.alb_health_check_interval
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
        matcher             = "200"
      }

      stickiness = {
        enabled = false
        type    = "lb_cookie"
      }
    }
  }

  # HTTP listener configuration
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "web"
      }
    }
  }

  tags = {
    Component = "load-balancer"
  }
}

# ============================================================================
# ALB Readiness Wait
# ============================================================================

resource "time_sleep" "alb_ready" {
  depends_on = [module.alb]

  create_duration = "30s"

  triggers = {
    alb_arn = module.alb.arn
  }
}

# ============================================================================
# Auto Scaling Group
# ============================================================================

module "autoscaling" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "~> 9.0"

  name                = "${local.naming_prefix}-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids

  # Launch template configuration
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.asg_instances.id # Will be created in Item 4
  ]

  # Capacity configuration
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  # Health check configuration
  health_check_type         = "ELB"
  health_check_grace_period = var.asg_health_check_grace_period

  # ALB integration via traffic source attachments
  traffic_source_attachments = {
    web = {
      traffic_source_identifier = module.alb.target_groups["web"].arn
    }
  }

  # Target tracking scaling policy for CPU utilization
  scaling_policies = {
    cpu_target_tracking = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = var.cpu_target_value
      }
    }
  }

  # CloudWatch metrics collection
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  tags = {
    Component = "compute"
  }

  depends_on = [time_sleep.alb_ready]
}
