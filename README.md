# Consumer ASG Deployment

**Feature**: 001-consumer-asg  
**Provider**: AWS  
**Terraform**: >= 1.14  
**HCP Terraform Org**: hashi-demos-apj  
**Workspace**: sandbox_consumer_asg_workspace

---

## Overview

This Terraform configuration provisions a scalable web application infrastructure consisting of:

- **Auto Scaling Group** of EC2 instances (Amazon Linux 2, t3.micro) with target tracking scaling based on CPU utilization (70% target)
- **Application Load Balancer** with HTTP listener and health checks for traffic distribution
- **CloudWatch monitoring** with 4 metric alarms (CPU utilization, response time, HTTP 5xx errors, unhealthy hosts)
- **Security groups** implementing least-privilege network controls (ALB → ASG communication only)

The deployment uses existing default VPC infrastructure to minimize cost and is optimized for development/sandbox environments in the `ap-southeast-2` region.

### Architecture Diagram

```
                                     ┌─────────────────────────────┐
                                     │                             │
                        ┌────────────┤   Application Load Balancer │
                        │            │   (Internet-facing)         │
Internet (0.0.0.0/0) ───┤            │   Port 80 (HTTP)            │
                        │            └─────────────────────────────┘
                        │                         │
                        │                         │ Target Group: web
                        │                         │ Health checks: /
                        │                         │
                        │            ┌────────────┴─────────────────┐
                        │            │                              │
                        │    ┌───────▼──────┐           ┌──────────▼────────┐
                        │    │  EC2 Instance │           │   EC2 Instance    │
                        │    │  (ASG Member)  │    ...    │   (ASG Member)    │
                        │    │  t3.micro      │           │   t3.micro        │
                        │    └────────────────┘           └───────────────────┘
                        │    ap-southeast-2a               ap-southeast-2b
                        │
                        │    Auto Scaling Group (1-3 instances)
                        │    - Min: 1, Max: 3, Desired: 1
                        └──  - Target Tracking: 70% CPU
                             - Health check type: ELB
                             - Grace period: 300s

                             ┌─────────────────────────────┐
                             │   CloudWatch Alarms         │
                             ├─────────────────────────────┤
                             │ • ASG CPU > 80%             │
                             │ • ALB Response Time > 1s    │
                             │ • ALB 5xx Errors > 10       │
                             │ • Unhealthy Hosts > 0       │
                             └─────────────────────────────┘
```

---

## Prerequisites

### 1. HCP Terraform Workspace

Ensure the target workspace is configured in your HCP Terraform organization:

- **Organization**: `hashi-demos-apj`
- **Project**: `sandbox` (prj-L3wMGgv1MTDuLBW4)
- **Workspace**: `sandbox_consumer_asg_workspace`
- **Execution Mode**: Remote
- **Terraform Version**: >= 1.14 (configured in workspace settings)

### 2. Dynamic Credentials Variable Set

This deployment requires the `agent_AWS_Dynamic_Creds` variable set to be attached to the workspace for OIDC-based AWS authentication:

- **Variable Set ID**: `varset-9BtXAvxByVGEnHWV`
- **Variables**:
  - `TFC_AWS_PROVIDER_AUTH = true` (enables dynamic credentials)
  - `TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::<ACCOUNT>:role/terraform` (IAM role for Terraform runs)
  - `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` (OIDC audience configuration)

**Security**: This deployment does NOT use static AWS access keys. All authentication is via temporary credentials issued by AWS STS through HCP Terraform's workload identity.

### 3. Private Registry Module Access

Ensure your organization has access to the following private registry modules:

- `hashi-demos-apj/autoscaling/aws` (version ~> 9.0)
- `hashi-demos-apj/alb/aws` (version ~> 10.1)
- `hashi-demos-apj/cloudwatch/aws` (version ~> 5.7)

### 4. AWS Resources

- **Default VPC**: Must exist in target region (`ap-southeast-2`)
- **Default Subnets**: Must exist in availability zones `ap-southeast-2a` and `ap-southeast-2b`
- **IAM Permissions**: Dynamic credential role must have permissions to:
  - Create/manage EC2 instances, Auto Scaling Groups, Launch Templates
  - Create/manage Application Load Balancers, Target Groups, Listeners
  - Create/manage Security Groups and Security Group Rules
  - Create/manage CloudWatch Alarms
  - Query VPC, Subnet, and AMI data sources

---

## Usage

### 1. Initialize Terraform

Initialize the Terraform working directory and download required providers and modules:

```bash
terraform init
```

This command:
- Configures the HCP Terraform backend (remote state storage)
- Downloads the AWS and Time providers
- Downloads private registry modules from `app.terraform.io/hashi-demos-apj`

### 2. Create Variable File

Copy the example variable file and customize values:

```bash
cp terraform.auto.tfvars.example terraform.auto.tfvars
```

Edit `terraform.auto.tfvars` and set at minimum:

```hcl
owner = "your-email@example.com"  # REQUIRED
```

Other variables have sensible defaults for development environments.

### 3. Plan Deployment

Review the execution plan to verify resources to be created:

```bash
terraform plan
```

Expected resource count: ~15 resources
- 2 module calls (ALB, ASG)
- 4 CloudWatch alarm submodules
- 3 security group resources (1 group, 2 rules)
- 1 time_sleep resource
- 3 data sources (VPC, subnets, AMI)

### 4. Apply Configuration

Deploy the infrastructure:

```bash
terraform apply
```

Deployment typically completes in 3-5 minutes:
- ALB creation: ~1-2 minutes
- 30-second wait for ALB target group readiness
- ASG creation and first instance launch: ~1-2 minutes
- CloudWatch alarms: ~10 seconds

### 5. Access Application

After apply completes, retrieve the ALB DNS name:

```bash
terraform output alb_dns_name
```

Access the application via HTTP:

```bash
curl http://$(terraform output -raw alb_dns_name)
```

**Note**: Initial requests may return 503 errors during instance health check grace period (up to 300 seconds). Wait for target health checks to pass before expecting successful responses.

### 6. Destroy Resources

Remove all provisioned infrastructure:

```bash
terraform destroy
```

**Warning**: This permanently deletes all resources. Ensure no production workloads depend on this infrastructure.

---

## Input Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `aws_region` | `string` | `"ap-southeast-2"` | No | AWS region for resource deployment |
| `project_name` | `string` | `"consumer-asg"` | No | Project identifier for resource naming and tagging |
| `environment` | `string` | `"development"` | No | Environment name (development, staging, production) |
| `owner` | `string` | -- | **Yes** | Owner email or team identifier for resource accountability |
| `instance_type` | `string` | `"t3.micro"` | No | EC2 instance type for ASG launch template (must be t2.* or t3.*) |
| `asg_min_size` | `number` | `1` | No | Minimum number of EC2 instances in Auto Scaling Group |
| `asg_max_size` | `number` | `3` | No | Maximum number of EC2 instances in Auto Scaling Group |
| `asg_desired_capacity` | `number` | `1` | No | Initial desired number of EC2 instances in Auto Scaling Group |
| `asg_health_check_grace_period` | `number` | `300` | No | Time in seconds after instance launch before health checks start |
| `cpu_target_value` | `number` | `70.0` | No | Target CPU utilization percentage for auto-scaling policy |
| `alb_health_check_path` | `string` | `"/"` | No | HTTP path for ALB target group health checks |
| `alb_health_check_interval` | `number` | `30` | No | Time in seconds between ALB health checks |
| `alarm_cpu_threshold` | `number` | `80.0` | No | CPU utilization percentage threshold for CloudWatch alarm |
| `alarm_response_time_threshold` | `number` | `1.0` | No | ALB target response time in seconds threshold for CloudWatch alarm |

### Variable Validation

All variables include validation rules:
- `aws_region`: Must match AWS region format (e.g., `ap-southeast-2`, `us-east-1`)
- `environment`: Must be one of `development`, `staging`, `production`
- `owner`: Must be non-empty string
- `instance_type`: Must match `t2.*` or `t3.*` pattern
- `asg_min_size`: Must be >= 0 and <= `asg_max_size`
- `asg_max_size`: Must be >= 1 and <= 10
- `alb_health_check_path`: Must start with `/`
- `cpu_target_value`: Must be > 0 and <= 100
- `alarm_cpu_threshold`: Must be > 0 and <= 100

---

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `alb_dns_name` | `string` | DNS name of the Application Load Balancer for accessing the application |
| `alb_arn` | `string` | ARN of the Application Load Balancer for CloudWatch metrics and logging configuration |
| `alb_zone_id` | `string` | Route53 hosted zone ID of the ALB for DNS alias record creation |
| `asg_id` | `string` | Auto Scaling Group identifier for AWS console reference |
| `asg_name` | `string` | Auto Scaling Group name for CloudWatch metrics and API operations |
| `asg_arn` | `string` | ARN of the Auto Scaling Group for IAM policy attachments and monitoring |
| `launch_template_id` | `string` | Launch template identifier for AMI update workflows |
| `vpc_id` | `string` | VPC ID used for deployment for networking context |
| `subnet_ids` | `list(string)` | Subnet IDs used for ALB and ASG placement |
| `asg_security_group_id` | `string` | Security group ID for ASG instances for manual rule additions |

### Output Usage Examples

**Access the application**:
```bash
# Get ALB DNS name
terraform output alb_dns_name

# Access via HTTP
curl http://$(terraform output -raw alb_dns_name)
```

**View CloudWatch metrics in AWS Console**:
```bash
# Get ASG name for metrics lookup
terraform output asg_name

# Get ALB ARN for metrics lookup
terraform output alb_arn
```

**Update launch template AMI**:
```bash
# Get launch template ID
terraform output launch_template_id

# Use with AWS CLI to create new version with updated AMI
aws ec2 create-launch-template-version \
  --launch-template-id $(terraform output -raw launch_template_id) \
  --source-version 1 \
  --launch-template-data "ImageId=ami-new-version"
```

---

## Module Dependencies

This deployment composes infrastructure from the following private registry modules:

| Module | Registry Source | Version | Purpose |
|--------|----------------|---------|---------|
| **autoscaling** | `app.terraform.io/hashi-demos-apj/autoscaling/aws` | `~> 9.0` | Auto Scaling Group with launch template, target tracking scaling policies, IMDSv2 enforcement, and traffic source attachments |
| **alb** | `app.terraform.io/hashi-demos-apj/alb/aws` | `~> 10.1` | Application Load Balancer with target groups, HTTP listener, health checks, and automatic security group creation |
| **cloudwatch_alarm** | `app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` | `~> 5.7` | CloudWatch metric alarms for ASG and ALB monitoring (4 instances: CPU, response time, 5xx errors, unhealthy hosts) |

### Module Wiring

Key module connections:

- `data.aws_vpc.default.id` → `module.alb.vpc_id` and `module.alb.target_groups["web"].vpc_id`
- `data.aws_subnets.default.ids` → `module.alb.subnets` and `module.autoscaling.vpc_zone_identifier`
- `data.aws_ami.amazon_linux_2.id` → `module.autoscaling.image_id`
- `module.alb.target_groups["web"].arn` → `module.autoscaling.traffic_source_attachments["web"].traffic_source_identifier`
- `module.alb.security_group_id` → `aws_vpc_security_group_ingress_rule.asg_from_alb.referenced_security_group_id`
- `module.autoscaling.autoscaling_group_name` → `module.cloudwatch_alarm_asg_cpu.dimensions.AutoScalingGroupName`
- `module.alb.arn_suffix` → CloudWatch alarm dimensions for ALB metrics

### Glue Resources

Minimal glue resources for network security and data queries:

- **Data sources**: `aws_vpc`, `aws_subnets`, `aws_ami` (query existing infrastructure)
- **Security groups**: `aws_security_group` for ASG instances, `aws_vpc_security_group_ingress_rule` for ALB-to-ASG traffic, `aws_vpc_security_group_egress_rule` for ASG outbound
- **Timing**: `time_sleep` resource for 30-second wait after ALB creation before ASG attachment

---

## Troubleshooting

### 1. terraform init fails with "Module not found"

**Symptom**: 
```
Error: Failed to query available provider packages
Module not found: app.terraform.io/hashi-demos-apj/autoscaling/aws
```

**Cause**: HCP Terraform authentication not configured or organization access denied.

**Solution**:
```bash
# Authenticate with HCP Terraform
terraform login

# Verify organization access
terraform workspace list

# Ensure you're using the correct workspace
terraform workspace select sandbox_consumer_asg_workspace
```

### 2. terraform plan fails with "Error: default vpc not found"

**Symptom**:
```
Error: no matching VPC found
  on data.tf line 1, in data "aws_vpc" "default":
   1: data "aws_vpc" "default" {
```

**Cause**: Default VPC does not exist in target region or was deleted.

**Solution**:
```bash
# Create default VPC in AWS Console or via AWS CLI
aws ec2 create-default-vpc --region ap-southeast-2

# Or change aws_region variable to region with existing default VPC
```

### 3. terraform apply fails with "UnauthorizedOperation"

**Symptom**:
```
Error: creating EC2 Launch Template: UnauthorizedOperation: You are not authorized to perform this operation
```

**Cause**: Dynamic credential IAM role lacks required permissions.

**Solution**:
- Verify `agent_AWS_Dynamic_Creds` variable set is attached to workspace
- Check IAM role `TFC_AWS_RUN_ROLE_ARN` has policies for EC2, Auto Scaling, ALB, CloudWatch
- Required managed policies: `AmazonEC2FullAccess`, `ElasticLoadBalancingFullAccess`, `CloudWatchFullAccess` (or equivalent custom policies)

### 4. ALB health checks fail — targets remain unhealthy

**Symptom**:
```
All targets failing health checks, application returns 503 Service Unavailable
```

**Cause**: EC2 instances not running web server on port 80, or health check path returns non-200 status.

**Solution**:
- Verify instance user data configures web server (not included in this deployment — application deployment out of scope)
- Check security group allows ALB → ASG traffic on port 80:
  ```bash
  terraform output asg_security_group_id
  aws ec2 describe-security-group-rules --filters "Name=group-id,Values=<sg-id>"
  ```
- Increase `asg_health_check_grace_period` to allow more time for application startup

### 5. Auto Scaling not triggering despite high CPU

**Symptom**:
ASG does not scale out even when CPU exceeds `cpu_target_value` (70%).

**Cause**: Target tracking policy requires sustained metric above threshold for scale-out cooldown period.

**Solution**:
- Verify scaling policy is active:
  ```bash
  aws autoscaling describe-policies \
    --auto-scaling-group-name $(terraform output -raw asg_name)
  ```
- Check CloudWatch metrics for ASG:
  ```bash
  aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value=$(terraform output -raw asg_name) \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
  ```
- Lower `cpu_target_value` to trigger scaling sooner (e.g., 50%)

### 6. terraform destroy fails with resource dependencies

**Symptom**:
```
Error: deleting ALB Target Group: ResourceInUse: Target group is currently in use by a listener
```

**Cause**: ASG instances still registered with target group during destroy.

**Solution**:
```bash
# Set ASG desired capacity to 0 to deregister instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $(terraform output -raw asg_name) \
  --desired-capacity 0

# Wait for instances to terminate (30-60 seconds)
sleep 60

# Retry destroy
terraform destroy
```

### 7. No default subnets in specified availability zones

**Symptom**:
```
Error: no subnets found matching filters
  on data.tf line 5, in data "aws_subnets" "default":
   5: data "aws_subnets" "default" {
```

**Cause**: Default VPC does not have subnets in `ap-southeast-2a` or `ap-southeast-2b`.

**Solution**:
- Check available subnets:
  ```bash
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"
  ```
- Update `locals.tf` availability zones to match existing default subnets:
  ```hcl
  availability_zones = [
    "ap-southeast-2a",
    "ap-southeast-2c"  # Change to match available AZ
  ]
  ```

### 8. CloudWatch alarms remain in INSUFFICIENT_DATA state

**Symptom**:
CloudWatch alarms show `INSUFFICIENT_DATA` status 10+ minutes after deployment.

**Cause**: Metrics not yet published by AWS (ASG or ALB not yet processing traffic).

**Solution**:
- Wait 5-10 minutes for initial metric collection
- Generate traffic to ALB to trigger metric publication:
  ```bash
  for i in {1..100}; do curl http://$(terraform output -raw alb_dns_name); done
  ```
- Verify metrics are being published:
  ```bash
  aws cloudwatch list-metrics --namespace AWS/ApplicationELB
  aws cloudwatch list-metrics --namespace AWS/EC2
  ```

---

## Security Notes

### 1. Security Overrides

This deployment includes two documented security overrides for development environment use:

- **No HTTPS/TLS encryption**: ALB uses HTTP-only listener (port 80) without TLS certificates. TLS certificate management is out of scope for development/sandbox environment. **Production deployments must add HTTPS listener with ACM certificate.**

- **No ALB access logs**: ALB access logging is disabled to avoid S3 bucket provisioning and cost. **Production deployments must enable access logs for audit and security compliance.**

Both overrides are documented in `consumer-design.md` Section 4 (Security Controls).

### 2. IMDSv2 Enforcement

EC2 instances enforce Instance Metadata Service Version 2 (IMDSv2) via the autoscaling module's default configuration. IMDSv1 is not available, preventing SSRF attacks against instance metadata.

### 3. Least-Privilege Network Controls

Security groups implement least-privilege network access:
- **ALB security group**: Ingress 0.0.0.0/0:80 (public HTTP), egress to ASG security group only
- **ASG security group**: Ingress from ALB security group on port 80 only, egress 0.0.0.0/0 for package updates

EC2 instances are NOT publicly accessible — all traffic routes through ALB.

### 4. No Static Credentials

This deployment uses HCP Terraform dynamic credentials via OIDC. AWS authentication is performed via temporary STS credentials with automatic rotation. No AWS access keys are stored in code or HCP Terraform workspace variables.

### 5. Resource Tagging

All resources are automatically tagged via provider `default_tags` for governance and cost allocation:
- `ManagedBy = "terraform"`
- `Environment = var.environment`
- `Project = var.project_name`
- `Owner = var.owner`
- `Deployment = "consumer-asg"`

---

## Cost Estimate

Estimated monthly cost for default configuration (ap-southeast-2 region):

| Resource | Units | Unit Cost | Monthly Cost |
|----------|-------|-----------|--------------|
| EC2 t3.micro | 1 instance (min) | $0.0146/hour | ~$10.66 |
| EC2 t3.micro | 2 instances (scale-out) | $0.0146/hour | +$21.32 (during scale) |
| Application Load Balancer | 1 ALB | $0.027/hour | ~$19.71 |
| ALB data processing | 10 GB/month | $0.008/GB | ~$0.08 |
| CloudWatch alarms | 4 alarms | $0.10/alarm | $0.40 |
| CloudWatch metrics | ASG metrics | Free (first 10 metrics) | $0.00 |
| **Total (minimum)** | | | **~$30.85/month** |
| **Total (scale-out to 3)** | | | **~$52.17/month** |

**Note**: Costs are estimates based on AWS ap-southeast-2 pricing as of 2025. Actual costs may vary based on traffic volume, data transfer, and AWS pricing changes.

---

## License

See `LICENSE` file in repository root.

---

## Support

For issues or questions:
- **Internal**: Contact platform-team or owner specified in `owner` variable
- **Terraform Issues**: Open issue in repository with `terraform plan` and `terraform apply` output
- **AWS Issues**: Check AWS Service Health Dashboard for region-specific outages

---

**Last Updated**: 2025-03-03  
**Terraform Version**: >= 1.14  
**Provider Version**: AWS ~> 6.19
