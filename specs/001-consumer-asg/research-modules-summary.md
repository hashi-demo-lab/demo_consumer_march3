# Private Registry Module Research Summary

## Organization: hashi-demos-apj

### Executive Summary

The hashi-demos-apj private registry contains all necessary modules for composing an ASG+ALB+CloudWatch infrastructure stack. Three primary modules were identified:

1. **autoscaling** v9.0.2 - Auto Scaling Groups with launch templates
2. **alb** v10.1.0 - Application Load Balancers with target groups
3. **cloudwatch** v5.7.2 - CloudWatch monitoring resources

Supporting infrastructure modules are also available: **vpc** v6.5.0, **security-group** v5.3.1, and **ec2-instance** v6.4.1.

All modules follow consistent naming conventions, use secure defaults, and provide comprehensive input/output interfaces for cross-module wiring.

---

## Core Infrastructure Modules

### 1. Auto Scaling Group Module

**Module ID**: `hashi-demos-apj/autoscaling/aws`  
**Latest Version**: 9.0.2  
**Created**: 2025-11-05  
**Provider**: AWS >= 6.12

**Purpose**: Provisions AWS Auto Scaling Groups with launch templates, IAM roles, schedules, and policies.

**Key Inputs**:
- `name` (string) - Name for ASG and launch template
- `min_size`, `max_size`, `desired_capacity` (number) - Scaling limits
- `vpc_zone_identifier` (list(string)) - Subnet IDs for instance placement
- `target_group_arns` (list(string)) - ALB target group ARNs for attachment
- `image_id` (string) - AMI ID for instances
- `instance_type` (string) - EC2 instance type
- `security_groups` (list(string)) - Security group IDs
- `user_data` (string) - Base64-encoded user data
- `metadata_options` (object) - IMDSv2 configuration (default: http_tokens=required)
- `health_check_type` (string) - EC2 or ELB health checks
- `health_check_grace_period` (number) - Health check delay
- `instance_refresh` (object) - Rolling update configuration
- `enabled_metrics` (list(string)) - CloudWatch metrics to collect
- `create_iam_instance_profile` (bool) - Create IAM instance profile

**Key Outputs**:
- `autoscaling_group_id` (string) - ASG identifier
- `autoscaling_group_name` (string) - ASG name
- `autoscaling_group_arn` (string) - ASG ARN for CloudWatch
- `launch_template_id` (string) - Launch template ID
- `launch_template_arn` (string) - Launch template ARN
- `iam_instance_profile_arn` (string) - IAM instance profile ARN
- `iam_role_arn` (string) - IAM role ARN
- `autoscaling_group_target_group_arns` (list(string)) - Attached target groups

**Secure Defaults**:
- IMDSv2 enforced by default (`http_tokens = "required"`)
- IAM instance profile creation supported
- Cross-zone load balancing enabled

**Wiring Notes**:
- Requires `target_group_arns` output from ALB module
- Requires `private_subnets` output from VPC module (list(string))
- Requires `security_group_id` output from security-group module
- Outputs ASG ARN for CloudWatch alarm attachment

---

### 2. Application Load Balancer Module

**Module ID**: `hashi-demos-apj/alb/aws`  
**Latest Version**: 10.1.0  
**Created**: 2025-11-03  
**Provider**: AWS >= 6.19

**Purpose**: Provisions Application Load Balancers, target groups, listeners, listener rules, and Route53 records.

**Key Inputs**:
- `name` (string) - Load balancer name
- `internal` (bool) - Internal or internet-facing (default: false)
- `subnets` (list(string)) - Subnet IDs for ALB placement
- `security_groups` (list(string)) - Security group IDs
- `vpc_id` (string) - VPC ID for target groups
- `enable_deletion_protection` (bool) - Deletion protection (default: true)
- `drop_invalid_header_fields` (bool) - Drop invalid headers (default: true)
- `enable_cross_zone_load_balancing` (bool) - Cross-zone LB (default: true)
- `access_logs` (object) - S3 access logging configuration
- `target_groups` (map(object)) - Target group definitions with health checks
  - `port`, `protocol`, `protocol_version`
  - `health_check` - path, interval, timeout, thresholds
  - `stickiness` - session stickiness config
  - `deregistration_delay` - connection draining
  - `target_type` - instance, ip, lambda
  - `vpc_id` - VPC for target group
- `listeners` (map(object)) - Listener configurations
- `listener_rules` (map(object)) - Routing rules
- `route53_records` (map(object)) - DNS record creation

**Key Outputs**:
- `id` (string) - Load balancer ID/ARN
- `arn` (string) - Load balancer ARN
- `arn_suffix` (string) - ARN suffix for CloudWatch metrics
- `dns_name` (string) - ALB DNS name
- `zone_id` (string) - Route53 zone ID for alias records
- `target_groups` (map) - Target group details including ARNs
  - Each target group map contains: `arn`, `id`, `name`, `arn_suffix`
- `listeners` (map) - Listener details
- `security_group_id` (string) - Created security group ID
- `route53_records` (map) - Created Route53 records

**Secure Defaults**:
- Deletion protection enabled
- Invalid header dropping enabled
- Cross-zone load balancing enabled
- Creates security group automatically

**Wiring Notes**:
- Requires `public_subnets` output from VPC module (list(string)) for internet-facing
- Requires `private_subnets` for internal ALBs
- Requires `vpc_id` output from VPC module (string)
- Outputs `target_groups[*].arn` → feeds into ASG `target_group_arns` input
- Outputs `arn_suffix` for CloudWatch metric namespace
- Security group can be referenced by other modules

---

### 3. CloudWatch Module

**Module ID**: `hashi-demos-apj/cloudwatch/aws`  
**Latest Version**: 5.7.2  
**Created**: 2025-11-15  
**Provider**: AWS >= 5.0

**Purpose**: Provisions CloudWatch log groups, metric filters, alarms, dashboards, and log streams.

**Submodules Available**:
- `modules/log-metric-filter` - Create metric filters from log patterns
- `modules/log-group` - CloudWatch log groups
- `modules/log-stream` - Log streams
- `modules/metric-alarm` - CloudWatch alarms
- `modules/metric-alarms-by-multiple-dimensions` - Batch alarm creation
- `modules/cis-alarms` - CIS AWS Foundations benchmark alarms
- `modules/composite-alarm` - Composite alarms
- `modules/query-definition` - CloudWatch Insights queries
- `modules/metric-stream` - Metric streaming to Kinesis
- `modules/log-subscription-filter` - Log subscription filters
- `modules/log-data-protection-policy` - Data protection policies

**Key Input Patterns** (vary by submodule):

**For `metric-alarm`**:
- `alarm_name` (string) - Alarm identifier
- `alarm_description` (string) - Alarm description
- `comparison_operator` (string) - Threshold comparison
- `evaluation_periods` (number) - Evaluation periods
- `threshold` (number) - Alarm threshold
- `namespace` (string) - CloudWatch metric namespace (e.g., "AWS/ApplicationELB", "AWS/EC2")
- `metric_name` (string) - Metric name (e.g., "TargetResponseTime", "CPUUtilization")
- `statistic` (string) - Statistic type (Average, Sum, Maximum)
- `period` (number) - Metric evaluation period
- `dimensions` (map(string)) - Metric dimensions (e.g., `{LoadBalancer = "app/my-alb/50dc6c495c0c9188"}`)
- `alarm_actions` (list(string)) - SNS topic ARNs for notifications
- `treat_missing_data` (string) - Missing data treatment

**For `log-group`**:
- `name` (string) - Log group name
- `retention_in_days` (number) - Log retention period
- `kms_key_id` (string) - KMS key for encryption

**Key Output Patterns** (vary by submodule):

**From `metric-alarm`**:
- `alarm_arn` (string) - CloudWatch alarm ARN
- `alarm_id` (string) - Alarm identifier

**From `log-group`**:
- `log_group_name` (string) - Log group name
- `log_group_arn` (string) - Log group ARN

**Secure Defaults**:
- Supports KMS encryption for log groups
- CIS benchmark alarms available
- Data protection policies for PII redaction

**Wiring Notes**:
- ALB CloudWatch alarms need:
  - `dimensions = {LoadBalancer = module.alb.arn_suffix}`
  - `namespace = "AWS/ApplicationELB"`
  - Metrics: `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, `HealthyHostCount`
- ASG CloudWatch alarms need:
  - `dimensions = {AutoScalingGroupName = module.asg.autoscaling_group_name}`
  - `namespace = "AWS/EC2"`
  - Metrics: `CPUUtilization`, `NetworkIn`, `NetworkOut`
- EC2 instance logs can be sent to CloudWatch log groups
- SNS topic ARN required for `alarm_actions`

---

## Supporting Infrastructure Modules

### 4. VPC Module

**Module ID**: `hashi-demos-apj/vpc/aws`  
**Latest Version**: 6.5.0  
**Created**: 2025-10-26  
**Provider**: AWS >= 5.0

**Purpose**: Provisions VPC with subnets, route tables, NAT gateways, and internet gateways.

**Key Outputs**:
- `vpc_id` (string) - VPC identifier
- `vpc_cidr_block` (string) - VPC CIDR block
- `public_subnets` (list(string)) - Public subnet IDs
- `private_subnets` (list(string)) - Private subnet IDs
- `database_subnets` (list(string)) - Database subnet IDs
- `natgw_ids` (list(string)) - NAT Gateway IDs
- `igw_id` (string) - Internet Gateway ID
- `public_route_table_ids` (list(string)) - Public route table IDs
- `private_route_table_ids` (list(string)) - Private route table IDs

**Wiring Notes**:
- `vpc_id` → feeds into ALB, ASG, security-group modules
- `public_subnets` → feeds into internet-facing ALB
- `private_subnets` → feeds into ASG, internal ALB, EC2 instances

---

### 5. Security Group Module

**Module ID**: `hashi-demos-apj/security-group/aws`  
**Latest Version**: 5.3.1  
**Created**: 2025-11-03  
**Provider**: AWS >= 3.29

**Purpose**: Provisions security groups with ingress/egress rules.

**Key Outputs**:
- `security_group_id` (string) - Security group ID
- `security_group_arn` (string) - Security group ARN
- `security_group_name` (string) - Security group name
- `security_group_vpc_id` (string) - VPC ID

**Wiring Notes**:
- Requires `vpc_id` from VPC module
- Outputs `security_group_id` → feeds into ASG, ALB, EC2 instance modules
- Can reference other security groups for cross-SG rules

---

### 6. EC2 Instance Module

**Module ID**: `hashi-demos-apj/ec2-instance/aws`  
**Latest Version**: 6.1.4  
**Created**: 2025-11-03  
**Provider**: AWS >= 6.0

**Purpose**: Provisions standalone EC2 instances (not typically used with ASG, but available for bastion/jump hosts).

**Key Outputs**:
- `id` (string) - Instance ID
- `arn` (string) - Instance ARN
- `private_ip` (string) - Private IP address
- `public_ip` (string) - Public IP address
- `security_group_id` (string) - Created security group ID

---

## Variable Sets Available

### agent_AWS_Dynamic_Creds

**Variable Set ID**: varset-9BtXAvxByVGEnHWV  
**Scope**: Not global (attached to specific projects)  
**Attached Projects**:
- prj-L3wMGgv1MTDuLBW4
- prj-QueMgU3LXgV2Ag7s

**Variables**:
- 3 variables configured (likely AWS dynamic credentials via TFC/TFE)

**Usage Note**: This variable set provides AWS authentication. Consumer workspaces should attach this variable set to avoid hardcoding credentials.

---

## Composition Architecture for ASG+ALB+CloudWatch Stack

### Module Dependency Graph

```
vpc (foundation)
  ↓
  ├─→ security-group (ALB SG, ASG SG)
  ├─→ alb (internet-facing, public_subnets)
  │    ↓ target_groups[*].arn
  └─→ autoscaling (private_subnets, target_group_arns)
       ↓ autoscaling_group_name, autoscaling_group_arn
       └─→ cloudwatch (metric-alarms for ASG & ALB)
```

### Cross-Module Wiring

#### VPC → ALB
- `vpc_id` (string) → `alb.vpc_id`
- `public_subnets` (list(string)) → `alb.subnets` (for internet-facing)
- `private_subnets` (list(string)) → `alb.subnets` (for internal)

#### VPC → ASG
- `private_subnets` (list(string)) → `asg.vpc_zone_identifier`
- `vpc_id` (string) → required for security group creation

#### VPC → Security Groups
- `vpc_id` (string) → `security-group.vpc_id`

#### Security Groups → ALB
- `security_group_id` (string) → `alb.security_groups` (list)

#### Security Groups → ASG
- `security_group_id` (string) → `asg.security_groups` (list)

#### ALB → ASG
- `alb.target_groups["primary"].arn` (string) → `asg.target_group_arns` (list)
  - **CRITICAL**: ALB outputs `target_groups` as a map(object), need to extract `.arn` attribute
  - Example: `target_group_arns = [module.alb.target_groups["web"].arn]`

#### ALB → CloudWatch Alarms
- `alb.arn_suffix` (string) → `cloudwatch_alarm.dimensions.LoadBalancer`
- Example dimensions: `{LoadBalancer = module.alb.arn_suffix}`
- Namespace: `AWS/ApplicationELB`
- Metrics: `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, `UnHealthyHostCount`, `HealthyHostCount`

#### ASG → CloudWatch Alarms
- `asg.autoscaling_group_name` (string) → `cloudwatch_alarm.dimensions.AutoScalingGroupName`
- Example dimensions: `{AutoScalingGroupName = module.asg.autoscaling_group_name}`
- Namespace: `AWS/EC2`
- Metrics: `CPUUtilization`, `NetworkIn`, `StatusCheckFailed`

---

## Output Type Verification

**Critical for TDD**: All cross-module outputs have been verified via `get_private_module_details`:

### VPC Module Outputs
- `vpc_id`: **string**
- `public_subnets`: **list(string)** - List of subnet IDs
- `private_subnets`: **list(string)** - List of subnet IDs

### ALB Module Outputs
- `arn`: **string**
- `arn_suffix`: **string** - For CloudWatch dimensions
- `target_groups`: **map(object)** - Each target group has:
  - `.arn`: **string**
  - `.id`: **string**
  - `.name`: **string**
  - `.arn_suffix`: **string**
- `dns_name`: **string**
- `zone_id`: **string**
- `security_group_id`: **string**

### ASG Module Outputs
- `autoscaling_group_id`: **string**
- `autoscaling_group_name`: **string**
- `autoscaling_group_arn`: **string**
- `launch_template_id`: **string**
- `autoscaling_group_target_group_arns`: **list(string)**

### Security Group Module Outputs
- `security_group_id`: **string**
- `security_group_arn`: **string**

**No type transformations required** - all outputs match expected input types directly.

---

## Glue Resources Needed

### Random Resources
- `random_string` or `random_id` - For unique naming suffix if multiple stacks in same account
- Example: `"${var.environment}-${random_string.suffix.result}"`

### Null Resources (Optional)
- `null_resource` with `local-exec` - For post-deployment verification or scripting
- Not typically needed for basic ASG+ALB composition

### Data Sources
- `aws_ami` - To lookup latest AMI ID for ASG launch template
- `aws_availability_zones` - To dynamically determine AZ count for VPC subnets
- `aws_caller_identity` - For account-specific naming/tagging

---

## Recommendations

### 1. Module Selection
✅ **Use these private registry modules**:
- `hashi-demos-apj/vpc/aws` v6.5.0
- `hashi-demos-apj/security-group/aws` v5.3.1
- `hashi-demos-apj/alb/aws` v10.1.0
- `hashi-demos-apj/autoscaling/aws` v9.0.2
- `hashi-demos-apj/cloudwatch/aws` v5.7.2 (submodules: `metric-alarm`)

### 2. Architecture Pattern
Use **hub-and-spoke** composition:
1. VPC as foundation (hub)
2. Security groups reference VPC
3. ALB and ASG reference VPC + security groups
4. CloudWatch alarms reference ALB and ASG outputs

### 3. Security Considerations
- ✅ All modules enforce secure defaults (IMDSv2, encryption, deletion protection)
- ✅ Use `agent_AWS_Dynamic_Creds` variable set for authentication
- ✅ Enable ALB access logs to S3 for audit trail
- ✅ Configure CloudWatch alarms for monitoring
- ⚠️ Ensure security group rules follow least-privilege (ALB → ASG only on app port)

### 4. CloudWatch Monitoring Strategy
**Recommended alarms**:

**ALB Alarms**:
- `TargetResponseTime` > 1s (P95)
- `HTTPCode_Target_5XX_Count` > 10
- `UnHealthyHostCount` > 0
- `HealthyHostCount` < min_size

**ASG Alarms**:
- `CPUUtilization` > 80%
- `StatusCheckFailed` > 0
- `NetworkIn` for traffic monitoring

**Implementation**:
- Use `cloudwatch/modules/metric-alarm` submodule
- Use `cloudwatch/modules/metric-alarms-by-multiple-dimensions` for batch alarms
- Configure SNS topic for alarm notifications

### 5. Testing Strategy
**Unit tests** (terraform test):
- Verify VPC CIDR configuration
- Verify subnet count matches AZ count
- Verify security group rules are correct
- Verify ALB target group health check settings
- Verify ASG min/max/desired capacity

**Integration tests**:
- Verify ALB target group registers ASG instances
- Verify health checks pass
- Verify CloudWatch metrics are published
- Verify alarms trigger on threshold breach

### 6. Naming Convention
Consistent naming pattern recommended:
```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "vpc" {
  name = "${local.name_prefix}-vpc"
}

module "alb" {
  name = "${local.name_prefix}-alb"
}

module "asg" {
  name = "${local.name_prefix}-asg"
}
```

---

## Example Composition Snippet

```hcl
# VPC
module "vpc" {
  source  = "app.terraform.io/hashi-demos-apj/vpc/aws"
  version = "6.5.0"
  
  name = "my-app-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = false  # One per AZ for HA
}

# ALB Security Group
module "alb_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "5.3.1"
  
  name   = "my-app-alb-sg"
  vpc_id = module.vpc.vpc_id
  
  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP from internet"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS from internet"
    }
  ]
}

# ASG Security Group
module "asg_sg" {
  source  = "app.terraform.io/hashi-demos-apj/security-group/aws"
  version = "5.3.1"
  
  name   = "my-app-asg-sg"
  vpc_id = module.vpc.vpc_id
  
  ingress_with_source_security_group_id = [
    {
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      source_security_group_id = module.alb_sg.security_group_id
      description              = "HTTP from ALB"
    }
  ]
}

# Application Load Balancer
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "10.1.0"
  
  name     = "my-app-alb"
  internal = false
  
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]
  
  target_groups = {
    web = {
      name        = "my-app-web-tg"
      port        = 8080
      protocol    = "HTTP"
      target_type = "instance"
      vpc_id      = module.vpc.vpc_id
      
      health_check = {
        enabled             = true
        path                = "/health"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
        matcher             = "200"
      }
      
      deregistration_delay = 30
    }
  }
  
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      
      forward = {
        target_group_key = "web"
      }
    }
  }
}

# Auto Scaling Group
module "asg" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "9.0.2"
  
  name = "my-app-asg"
  
  min_size         = 2
  max_size         = 6
  desired_capacity = 2
  
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [module.alb.target_groups["web"].arn]
  
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  
  security_groups = [module.asg_sg.security_group_id]
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Application startup script
    EOF
  )
  
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize"
  ]
}

# CloudWatch Alarm - ALB Target Response Time
module "alb_response_time_alarm" {
  source = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"
  
  alarm_name          = "my-app-alb-high-response-time"
  alarm_description   = "ALB target response time is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1.0  # 1 second
  
  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"
  statistic   = "Average"
  period      = 60
  
  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# CloudWatch Alarm - ASG High CPU
module "asg_cpu_alarm" {
  source = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"
  
  alarm_name          = "my-app-asg-high-cpu"
  alarm_description   = "ASG instances have high CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  
  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  period      = 300
  
  dimensions = {
    AutoScalingGroupName = module.asg.autoscaling_group_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

---

## Sources

- HCP Terraform Private Registry: `app.terraform.io/hashi-demos-apj`
- Module Details: Retrieved via MCP `get_private_module_details` tool
- VCS Repository: `https://github.com/hashi-demo-lab/terraform-aws-*`
- AWS Documentation: Application Load Balancer, Auto Scaling, CloudWatch
