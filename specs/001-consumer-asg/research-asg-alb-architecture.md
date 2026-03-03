## Research: AWS architecture best practices for composing an Auto-Scaling Group with Application Load Balancer in ap-southeast-2

### Decision

Use private registry modules `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0 and `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2 — both modules provide secure defaults, comprehensive configuration options, and compatible interfaces for wiring ASG to ALB via target groups.

### Modules Identified

#### Primary Modules

- **ALB Module**: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0
  - **Purpose**: Creates Application Load Balancer with target groups, listeners, and security groups
  - **Key Inputs**: 
    - `name` or `name_prefix` — ALB name
    - `subnets` — list(string) of subnet IDs (requires 2+ AZs for ALB)
    - `internal` — bool, false for internet-facing (default: null)
    - `security_group_ingress_rules` — map for allowing HTTP/HTTPS traffic
    - `target_groups` — map(object) defining target group configurations
  - **Key Outputs**:
    - `target_groups` — map(object) containing target group attributes including ARNs
    - `arn` — ALB ARN
    - `dns_name` — ALB DNS name for testing
    - `security_group_id` — Security group ID created for ALB
  - **Secure Defaults**: 
    - `enable_deletion_protection` = true (configurable)
    - `drop_invalid_header_fields` = true
    - `enable_cross_zone_load_balancing` = true
    - Security group with controlled ingress/egress rules

- **ASG Module**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
  - **Purpose**: Creates Auto Scaling Group with launch template, IAM roles, and scaling policies
  - **Key Inputs**:
    - `name` — ASG name
    - `min_size`, `max_size`, `desired_capacity` — scaling bounds
    - `vpc_zone_identifier` — list(string) of subnet IDs
    - `target_group_arns` — list(string) of ALB target group ARNs (wiring point)
    - `health_check_type` — string: "EC2" or "ELB" 
    - `health_check_grace_period` — number (seconds)
    - `instance_type` — string (e.g., "t3.micro")
    - `scaling_policies` — map(object) for target tracking policies
    - `enabled_metrics` — list(string) for CloudWatch metrics
  - **Key Outputs**:
    - `autoscaling_group_name` — ASG name for CloudWatch dashboards
    - `autoscaling_group_arn` — ASG ARN
    - `autoscaling_group_id` — ASG ID
    - `launch_template_id` — Launch template ID
    - `iam_role_arn` — IAM role ARN for instances
  - **Secure Defaults**:
    - Creates IAM instance profile and role
    - Supports IAM role policies (e.g., AmazonSSMManagedInstanceCore)
    - EBS optimization available

#### Supporting Modules/Resources

- **Glue Resources Needed**:
  - `data "aws_vpc"` — to retrieve default VPC ID
  - `data "aws_subnets"` — to retrieve default subnets in ap-southeast-2
  - `data "aws_availability_zones"` — to filter available AZs
  - Optionally: `random_string` for unique naming suffix

### Wiring Considerations

#### 1. ASG to ALB Target Group Wiring

**Connection Pattern**:
```hcl
# ALB module outputs target group ARNs via map
module "alb" {
  target_groups = {
    web-instances = {
      name_prefix = "web-"
      port        = 80
      protocol    = "HTTP"
      target_type = "instance"
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }
    }
  }
}

# ASG module accepts list of target group ARNs
module "asg" {
  target_group_arns = [
    module.alb.target_groups["web-instances"].arn
  ]
}
```

**Output Type Verification**:
- `module.alb.target_groups` returns: `map(object)` with each target group's attributes
- Each target group object includes: `arn` (string), `id` (string), `name` (string)
- `module.asg` expects: `target_group_arns` as `list(string)` of ARNs
- **Wiring transformation**: Access map value `.arn` and wrap in list: `[module.alb.target_groups["web-instances"].arn]`

#### 2. Target Tracking Scaling Policies (CPU Utilization for Dev)

**Recommended Configuration for Development**:
```hcl
scaling_policies = {
  cpu-target-tracking = {
    policy_type = "TargetTrackingScaling"
    target_tracking_configuration = {
      predefined_metric_specification = {
        predefined_metric_type = "ASGAverageCPUUtilization"
      }
      target_value = 70.0  # 70% CPU for dev (less aggressive than prod 50%)
    }
  }
}
```

**Rationale**:
- **Development threshold**: 70% CPU allows for testing scaling behavior without excessive scale-outs
- **Production threshold**: 50-60% CPU (more headroom for traffic spikes)
- **Cooldown**: Default cooldown handled by target tracking (no explicit cooldown needed)
- **Scale-out speed**: Target tracking automatically calculates scale-out amount
- **Scale-in**: Gradual scale-in when CPU drops below target

#### 3. Health Check Configuration Between ALB and ASG

**ALB Target Group Health Check** (defined in ALB module):
```hcl
target_groups = {
  web-instances = {
    health_check = {
      enabled             = true
      healthy_threshold   = 2      # 2 consecutive successes = healthy
      unhealthy_threshold = 2      # 2 consecutive failures = unhealthy
      interval            = 30     # Check every 30 seconds
      path                = "/"    # Health check endpoint
      port                = "traffic-port"  # Use same port as target
      protocol            = "HTTP"
      timeout             = 5      # 5 second timeout
      matcher             = "200"  # Expected HTTP response code
    }
    deregistration_delay = 300     # 5 minutes drain time (can reduce to 60 for dev)
  }
}
```

**ASG Health Check Configuration** (defined in ASG module):
```hcl
health_check_type         = "ELB"  # Use ELB health checks (required when using ALB)
health_check_grace_period = 300    # 5 minutes for instance bootstrap
```

**Health Check Flow**:
1. Instance launches in ASG
2. ASG waits `health_check_grace_period` (300s) before starting health checks
3. ALB performs health checks every 30 seconds to instance
4. After 2 consecutive successes (60 seconds), instance marked healthy in target group
5. ASG considers instance healthy if ELB target group reports healthy
6. If 2 consecutive failures, instance marked unhealthy and ASG replaces it

**Recommendations for Development**:
- Reduce `health_check_grace_period` to 180-240s if application starts quickly
- Reduce `deregistration_delay` to 60s for faster iteration
- Keep `interval` at 30s (AWS minimum for ALB)
- Use `path = "/health"` or similar dedicated health endpoint if available

#### 4. Using Default VPC with 2 AZs in ap-southeast-2

**Availability Zones in ap-southeast-2** (Sydney):
- ap-southeast-2a
- ap-southeast-2b
- ap-southeast-2c

**Default VPC Pattern**:
```hcl
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["ap-southeast-2a", "ap-southeast-2b"]  # Select 2 AZs
  }
}

# ALB requires 2+ subnets in different AZs
module "alb" {
  subnets = data.aws_subnets.default.ids  # list(string)
}

# ASG uses same subnets for instance placement
module "asg" {
  vpc_zone_identifier = data.aws_subnets.default.ids  # list(string)
}
```

**Considerations**:
- **ALB Requirement**: Minimum 2 subnets in different AZs
- **Default VPC**: Has one subnet per AZ (usually 3 in ap-southeast-2)
- **Subnet Selection**: Explicitly filter to 2 AZs for cost control (fewer NAT gateways if adding private subnets later)
- **Cross-Zone Load Balancing**: Enabled by default in ALB module (no extra data transfer charges for ALB)

#### 5. Minimal Cost Configuration for Development Environment

**Instance Types and Sizing**:
```hcl
# ASG Configuration
instance_type     = "t3.micro"   # $0.0146/hour (~$10.66/month per instance)
# Alternative: "t3.small"        # $0.0292/hour (~$21.32/month) if t3.micro insufficient

min_size          = 1            # Minimum 1 instance for availability
max_size          = 3            # Cap at 3 instances to control costs
desired_capacity  = 1            # Start with 1 instance
```

**Cost Breakdown (ap-southeast-2 Sydney pricing)**:

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| **EC2 Instances** | 1x t3.micro (desired) | $10.66 |
| **EC2 Instances** | 3x t3.micro (max scale-out) | $32.00 |
| **ALB** | Application Load Balancer | $22.50 (hourly) + $0.008/LCU |
| **Data Transfer** | Out to internet | $0.114/GB after 100GB free |
| **EBS Storage** | 8GB gp3 root volume | $0.96/month |
| **CloudWatch** | Basic monitoring (5-min) | Free |
| **CloudWatch** | Detailed monitoring (1-min) | $2.10/month per instance |

**Total Estimated Cost** (development with 1 instance running):
- **Baseline**: ~$34/month (1 instance + ALB + storage)
- **Scale-out to 3**: ~$56/month
- **With detailed monitoring**: Add $2.10-$6.30/month

**Cost Optimization Strategies**:
1. **Use t3.micro for web tier**: Burstable CPU credits, adequate for dev workloads
2. **Set `desired_capacity = 1`**: Single instance for development
3. **Enable termination on scale-in**: Remove `protect_from_scale_in`
4. **Basic monitoring**: Don't enable `enable_monitoring = true` (saves $2.10/instance/month)
5. **Reduce deregistration delay**: 60s instead of 300s (faster testing, no cost impact)
6. **Consider Savings Plans**: Not applicable for dev (short-term usage)
7. **Auto-shutdown schedule**: Use ASG schedules to scale to 0 outside business hours

**Schedule Example for Dev Cost Savings**:
```hcl
schedules = {
  night = {
    min_size         = 0
    max_size         = 0
    desired_capacity = 0
    recurrence       = "0 21 * * MON-FRI"  # 9 PM weeknights
  }
  morning = {
    min_size         = 1
    max_size         = 3
    desired_capacity = 1
    recurrence       = "0 7 * * MON-FRI"   # 7 AM weekday mornings
  }
}
```

#### 6. CloudWatch Dashboard Metrics for ASG and ALB Monitoring

**Key Metrics to Monitor**:

**ASG Metrics** (namespace: AWS/EC2 + AWS/AutoScaling):
```hcl
enabled_metrics = [
  "GroupDesiredCapacity",
  "GroupInServiceInstances",
  "GroupMaxSize",
  "GroupMinSize",
  "GroupPendingInstances",
  "GroupStandbyInstances",
  "GroupTerminatingInstances",
  "GroupTotalInstances",
]
```

**CloudWatch Dashboard JSON Structure**:
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/AutoScaling", "GroupDesiredCapacity", {"stat": "Average"}],
          [".", "GroupInServiceInstances", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-southeast-2",
        "title": "ASG Instance Count"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/EC2", "CPUUtilization", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-southeast-2",
        "title": "EC2 CPU Utilization",
        "yAxis": {"left": {"min": 0, "max": 100}}
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "TargetResponseTime", {"stat": "Average"}],
          [".", "RequestCount", {"stat": "Sum"}],
          [".", "HealthyHostCount", {"stat": "Average"}],
          [".", "UnHealthyHostCount", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-southeast-2",
        "title": "ALB Performance"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", {"stat": "Sum"}],
          [".", "HTTPCode_Target_4XX_Count", {"stat": "Sum"}],
          [".", "HTTPCode_Target_5XX_Count", {"stat": "Sum"}]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "ap-southeast-2",
        "title": "Target HTTP Responses"
      }
    }
  ]
}
```

**Critical Metrics for Development**:

| Metric | Namespace | Purpose | Alert Threshold |
|--------|-----------|---------|-----------------|
| `GroupInServiceInstances` | AWS/AutoScaling | Track running instances | Alert if 0 |
| `CPUUtilization` | AWS/EC2 | Monitor instance load | Alert if >80% for 5 min |
| `HealthyHostCount` | AWS/ApplicationELB | Monitor target health | Alert if <1 |
| `TargetResponseTime` | AWS/ApplicationELB | Application performance | Alert if >2 seconds |
| `HTTPCode_Target_5XX_Count` | AWS/ApplicationELB | Application errors | Alert if >10 per 5 min |
| `RequestCount` | AWS/ApplicationELB | Traffic volume | Track for capacity planning |

**Terraform CloudWatch Dashboard Resource**:
```hcl
resource "aws_cloudwatch_dashboard" "asg_alb" {
  dashboard_name = "dev-asg-alb-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      # Widgets defined above
    ]
  })
}
```

**Additional Monitoring Recommendations**:
1. **Enable ALB Access Logs**: Store in S3 for detailed request analysis (costs apply)
2. **Set up CloudWatch Alarms**: For critical metrics (HealthyHostCount < 1)
3. **Use CloudWatch Insights**: Query ASG and ALB logs for troubleshooting
4. **Configure SNS notifications**: Alert on scaling events and health check failures

### Rationale

**Private Registry Modules Selected**:
- Both ALB and ASG modules exist in `hashi-demos-apj` organization with recent versions
- Modules are based on official `terraform-aws-modules` community patterns
- Output types are compatible: ALB outputs map(object) with ARN strings, ASG accepts list(string)
- No type transformations needed beyond simple map access and list wrapping

**Architecture Decisions**:
- **ELB Health Checks**: More accurate than EC2 health checks for application-level failures
- **Target Tracking Scaling**: Simpler and more responsive than step scaling
- **70% CPU Target**: Balances cost and responsiveness for development environment
- **2 AZs**: Minimum for ALB high availability while controlling costs
- **t3.micro**: Cost-effective for development, burstable CPU for occasional spikes
- **Basic Monitoring**: CloudWatch basic metrics are free and sufficient for dev

**Security Best Practices**:
- ALB security group limits ingress to HTTP/HTTPS
- ASG instances in security group accepting traffic only from ALB
- IAM instance profile with SSM for secure shell access (no SSH keys)
- EBS encryption available in launch template configuration
- Deletion protection enabled on ALB (disable for dev if frequent teardown)

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Classic Load Balancer | Deprecated, ALB offers better features and pricing |
| Network Load Balancer | Overkill for HTTP/HTTPS traffic, ALB is sufficient |
| EC2 health checks only | Less accurate than ELB health checks for application failures |
| Step scaling policies | More complex configuration, target tracking is simpler and effective |
| 3 AZs for dev | Increased cost without significant benefit for development |
| t3.nano instances | Insufficient CPU/memory for most web applications |
| t3a.micro (AMD) | Marginal savings ($0.0130/hr vs $0.0146/hr), limited availability |
| Spot instances | Interruptions unsuitable for development environment stability |
| Manual EC2 without ASG | No auto-healing, no auto-scaling, operational burden |
| Single AZ deployment | ALB requires minimum 2 AZs for high availability |

### Sources

- Private Registry: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0 module documentation
- Private Registry: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2 module documentation
- AWS Provider Docs: `aws_autoscaling_group` resource (hashicorp/aws 6.34.0)
- AWS Provider Docs: `aws_lb_target_group` resource (hashicorp/aws 6.34.0)
- AWS Documentation: Auto Scaling target tracking scaling policies
- AWS Documentation: Application Load Balancer target group health checks
- AWS Pricing: EC2 ap-southeast-2 (Sydney) pricing
- AWS Pricing: Application Load Balancer pricing
- Public Registry: Pattern research from cloudposse/ecs-web-app module
- AWS Best Practices: Multi-AZ deployment for high availability
