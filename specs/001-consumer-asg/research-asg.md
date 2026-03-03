## Research: What private registry modules are available for Auto Scaling Groups?

### Decision

Use `hashi-demos-apj/autoscaling/aws` v9.0.2 — provides complete ASG infrastructure with launch templates, IAM instance profiles, scaling policies, schedules, and IMDSv2 enforcement by default.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
  - **Purpose**: Provisions AWS Auto Scaling Groups with launch templates, IAM roles, schedules, and policies
  - **Key Inputs**: 
    - `name` (string) - ASG and launch template name
    - `min_size`, `max_size`, `desired_capacity` (number) - Scaling limits
    - `vpc_zone_identifier` (list(string)) - Subnet IDs for instance placement
    - `target_group_arns` (list(string)) - ALB target group ARNs for attachment
    - `image_id` (string) - AMI ID for instances
    - `instance_type` (string) - EC2 instance type (default: t3.micro)
    - `security_groups` (list(string)) - Security group IDs
    - `user_data` (string) - Base64-encoded user data
    - `health_check_type` (string) - "EC2" or "ELB"
    - `health_check_grace_period` (number) - Health check delay in seconds
    - `instance_refresh` (object) - Rolling update configuration
    - `enabled_metrics` (list(string)) - CloudWatch metrics to collect
    - `create_iam_instance_profile` (bool) - Whether to create IAM instance profile
    - `metadata_options` (object) - IMDSv2 configuration
  - **Key Outputs**: 
    - `autoscaling_group_id` (string) - ASG identifier
    - `autoscaling_group_name` (string) - ASG name for CloudWatch dimensions
    - `autoscaling_group_arn` (string) - ASG ARN
    - `launch_template_id` (string) - Launch template ID
    - `launch_template_arn` (string) - Launch template ARN
    - `iam_instance_profile_arn` (string) - IAM instance profile ARN
    - `iam_role_arn` (string) - IAM role ARN
    - `autoscaling_group_target_group_arns` (list(string)) - Attached target group ARNs
    - `autoscaling_group_min_size` (number) - Min size
    - `autoscaling_group_max_size` (number) - Max size
    - `autoscaling_group_desired_capacity` (number) - Desired capacity
  - **Secure Defaults**: 
    - IMDSv2 enforced (`http_tokens = "required"`)
    - IMDSv1 hop limit set to 1
    - IAM instance profile creation supported
    - Supports KMS encryption for EBS volumes
    - Cross-zone load balancing enabled
- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 — VPC with private subnets for instance placement
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — Security groups for instance network access
  - `app.terraform.io/hashi-demos-apj/ec2-instance/aws` v6.1.4 — Can provide AMI ID patterns, but not used directly with ASG
- **Glue Resources Needed**: 
  - `data "aws_ami"` - To lookup latest AMI ID for launch template
  - `random_string` - For unique naming suffix if needed
- **Wiring Considerations**: 
  - **Input from VPC**: `vpc_zone_identifier = module.vpc.private_subnets` (list(string))
  - **Input from Security Group**: `security_groups = [module.asg_sg.security_group_id]` (list(string))
  - **Input from ALB**: `target_group_arns = [module.alb.target_groups["web"].arn]` (list(string))
    - ⚠️ ALB outputs `target_groups` as map(object), must extract `.arn` attribute
  - **Output to CloudWatch**: 
    - `autoscaling_group_name` (string) → alarm dimensions `{AutoScalingGroupName = ...}`
    - `autoscaling_group_arn` (string) → can be used for tagging/tracking
  - **Type Compatibility**: All outputs verified as correct types — no transformations needed
    - VPC `private_subnets` is list(string) ✅
    - Security group `security_group_id` is string ✅
    - ALB `target_groups[key].arn` is string ✅

### Rationale

The `autoscaling` module is the only ASG module in the private registry and provides comprehensive functionality:
1. **Complete launch template support** — all EC2 launch parameters configurable
2. **Target group integration** — native support for `target_group_arns` list input
3. **IAM instance profile** — optional creation via `create_iam_instance_profile = true`
4. **Security by default** — IMDSv2 enforced, hop limit = 1
5. **CloudWatch metrics** — enables metric collection via `enabled_metrics` input
6. **Instance refresh** — supports rolling updates with configurable preferences
7. **Compatible interfaces** — outputs match CloudWatch alarm dimension requirements

Module created recently (2025-11-05) with provider constraint `>= 6.12`, indicating active maintenance.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| `hashi-demos-apj/ec2-instance/aws` | Single instance module, not for auto scaling |
| Public registry `terraform-aws-modules/autoscaling/aws` | Organization policy requires private registry modules |
| Raw `aws_autoscaling_group` + `aws_launch_template` | Consumer constitution prohibits raw resources |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj/autoscaling/aws`
- MCP tool: `get_private_module_details` output for version 9.0.2
- VCS repository: `https://github.com/hashi-demo-lab/terraform-aws-autoscaling`
- AWS docs: Auto Scaling Groups best practices
- AWS docs: IMDSv2 requirements
