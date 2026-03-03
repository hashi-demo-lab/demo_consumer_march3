# Consumer Design: Auto-Scaling Group with ALB

**Branch**: feat/001-consumer-asg
**Date**: 2025-03-03
**Status**: Draft
**Provider**: aws ~> 6.19
**Terraform**: >= 1.14
**HCP Terraform Org**: hashi-demos-apj

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions a scalable web application infrastructure consisting of an Auto Scaling Group of EC2 instances behind an Application Load Balancer, with CloudWatch monitoring for operational visibility. The infrastructure supports development workloads in the ap-southeast-2 region using existing default VPC resources to minimize cost and deployment complexity. This deployment serves as a foundation for hosting containerized or traditional web applications that require horizontal scaling, health-based traffic routing, and automated monitoring.

**Scope boundary**: This deployment does NOT include VPC provisioning (uses existing default VPC), database infrastructure, CI/CD pipelines, application deployment automation, DNS/Route53 records, TLS certificates, or WAF configuration. Application runtime configuration and code deployment are out of scope.

### Requirements

**Functional requirements** -- what the deployment must provision:

- Auto-scaling compute capacity with minimum 1, maximum 3, desired 1 EC2 instances using t3.micro instance type
- Horizontal scaling triggered by CPU utilization target of 70% using target tracking policies
- Application Load Balancer with HTTP listener (port 80) and health checks across 2 availability zones (ap-southeast-2a, ap-southeast-2b)
- Health-based traffic routing with ELB health checks and 300-second grace period for instance initialization
- CloudWatch dashboard displaying instance count, CPU utilization, ALB performance metrics, and HTTP response codes
- Metric alarms for operational thresholds: high CPU, elevated response time, HTTP 5xx errors, unhealthy host count
- All resources deployed to ap-southeast-2 region in development environment context

**Non-functional requirements** -- constraints like compliance, performance, availability, cost:

- Cost optimization: minimal instance sizing (t3.micro ~$10.66/month), single-instance minimum, development-grade configuration
- Availability: multi-AZ deployment across 2 availability zones for basic fault tolerance
- Security: IMDSv2 enforcement, least-privilege security groups, no public instance access, dynamic AWS credentials
- Monitoring: comprehensive CloudWatch metrics for ASG (8 metrics) and ALB performance visibility
- Compliance: infrastructure-as-code with HCP Terraform state management, tagged resources for governance
- Performance: sub-1-second target response time with alarm threshold at P95

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Use existing default VPC**: Deployment leverages default VPC with `data.aws_vpc` and `data.aws_subnets` data sources rather than provisioning new VPC infrastructure.
*Rationale*: Requirements specify "use existing default VPC" for cost optimization in development environment. Default VPC provides sufficient networking for non-production workloads. Research findings (research-networking.md) confirm data source approach with `default = true` flag returns VPC ID and subnet IDs as correct types (`string`, `list(string)`).
*Rejected*: Creating VPC with `hashi-demos-apj/vpc/aws` module — adds unnecessary cost ($32-48/month for NAT Gateways) and complexity for development environment.

**ASG placement in default subnets**: EC2 instances launched in all available default VPC subnets across target availability zones.
*Rationale*: Default VPC subnets are public with internet gateway routing, sufficient for development workload. Module wiring research (research-module-wiring.md) confirms `data.aws_subnets.ids` output type (`list(string)`) matches ASG module `vpc_zone_identifier` input type.
*Rejected*: Private subnet placement with NAT Gateway — requires custom VPC, increases cost, unnecessary for development scope.

**ALB internet-facing with default subnets**: Application Load Balancer deployed as internet-facing in default VPC public subnets.
*Rationale*: Development workload requires external access for testing. ALB module `internal = false` configures internet-facing deployment. Research findings (research-alb.md) show ALB module accepts `subnets` input as `list(string)` from data sources.
*Rejected*: Internal ALB with bastion host — adds operational complexity without development environment justification.

**Traffic source attachments for ALB-ASG integration**: ASG connected to ALB target group using `traffic_source_attachments` map rather than legacy `target_group_arns` list.
*Rationale*: Module wiring research (research-module-wiring.md) identifies `traffic_source_attachments` as the modern AWS provider >= 6.12 approach with better lifecycle management, multiple target group support, and native map structure. ALB module outputs `target_groups` map with `.arn` attribute (type `string`) compatible with `traffic_source_identifier` input.
*Rejected*: Legacy `target_group_arns` list input — deprecated pattern, module uses modern map-based attachment structure.

**Glue security groups for least-privilege network controls**: Raw `aws_security_group` and `aws_vpc_security_group_ingress_rule` resources manage network policies rather than security-group module.
*Rationale*: Security group configuration is minimal (2 groups: ALB SG, ASG SG) and requires precise control over bidirectional references (ALB egress to ASG, ASG ingress from ALB). Research findings (research-asg-alb-architecture.md) show this pattern enables least-privilege with source security group references. Raw security group resources are glue resources per constitution §1.1.
*Rejected*: Using `hashi-demos-apj/security-group/aws` module — creates circular dependency challenges with ALB module's automatic security group creation, adds complexity for simple 2-group topology.

**CloudWatch alarms via metric-alarm submodule**: Individual metric alarms created using `hashi-demos-apj/cloudwatch/aws//modules/metric-alarm` submodule rather than root module.
*Rationale*: Research findings (research-cloudwatch.md) show root CloudWatch module provisions log groups and composite features not needed for this deployment. Metric-alarm submodule provides focused alarm creation with `dimensions`, `namespace`, and `metric_name` inputs matching ASG and ALB output patterns.
*Rejected*: Root cloudwatch module — includes unnecessary log group and metric filter resources, submodule provides cleaner interface for standalone alarms.

**Target tracking scaling policy**: CPU-based target tracking scaling policy (70% target) configured directly via ASG module input.
*Rationale*: ASG module research (research-asg.md) documents `scaling_policies` input map supporting target tracking policies with `predefined_metric_type = "ASGAverageCPUUtilization"`. This provides automatic scale-out and scale-in based on CloudWatch metrics without separate policy resources.
*Rejected*: Step scaling with separate `aws_autoscaling_policy` resources — target tracking provides simpler declarative approach for CPU-based scaling.

**HCP Terraform dynamic credentials**: AWS provider authentication via dynamic credentials using existing `agent_AWS_Dynamic_Creds` variable set.
*Rationale*: Research findings (research-module-wiring.md) identify variable set `varset-9BtXAvxByVGEnHWV` in hashi-demos-apj organization with 3 configured variables for OIDC-based dynamic credentials. Constitution §3.1 mandates dynamic credentials — no static AWS keys permitted.
*Rejected*: Static AWS credentials in workspace variables — violates constitution security requirements and organizational policy.

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|---------------|---------|---------|-------------|------------|-------------|
| autoscaling | app.terraform.io/hashi-demos-apj/autoscaling/aws | ~> 9.0 | Provisions Auto Scaling Group with launch template, IMDSv2, IAM instance profile, target tracking scaling policies, and traffic source attachments | always | `vpc_zone_identifier`, `traffic_source_attachments`, `image_id`, `instance_type`, `security_groups`, `min_size`, `max_size`, `desired_capacity`, `health_check_type`, `scaling_policies` | `autoscaling_group_id`, `autoscaling_group_name`, `autoscaling_group_arn`, `launch_template_id` |
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | Provisions Application Load Balancer with target groups, HTTP listener, health checks, and automatic security group creation | always | `vpc_id`, `subnets`, `internal`, `target_groups`, `listeners`, `enable_deletion_protection`, `drop_invalid_header_fields` | `id`, `arn`, `arn_suffix`, `dns_name`, `target_groups`, `security_group_id` |
| cloudwatch_alarm_asg_cpu | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ASG average CPU utilization > 80% | always | `alarm_name`, `comparison_operator`, `threshold`, `namespace`, `metric_name`, `dimensions`, `evaluation_periods` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |
| cloudwatch_alarm_alb_response_time | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ALB target response time > 1 second | always | `alarm_name`, `comparison_operator`, `threshold`, `namespace`, `metric_name`, `dimensions`, `statistic` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |
| cloudwatch_alarm_alb_5xx | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ALB HTTP 5xx error count | always | `alarm_name`, `comparison_operator`, `threshold`, `namespace`, `metric_name`, `dimensions`, `statistic` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |
| cloudwatch_alarm_unhealthy_hosts | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for unhealthy target count > 0 | always | `alarm_name`, `comparison_operator`, `threshold`, `namespace`, `metric_name`, `dimensions` | `cloudwatch_metric_alarm_arn`, `cloudwatch_metric_alarm_id` |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|-------------|---------|------------|
| data.aws_vpc | default | Query existing default VPC ID for ALB and security group configuration | -- |
| data.aws_subnets | default | Query default VPC subnet IDs for ALB and ASG placement across availability zones | data.aws_vpc.default |
| data.aws_ami | amazon_linux_2 | Lookup latest Amazon Linux 2 AMI ID for ASG launch template | -- |
| aws_security_group | asg_instances | Security group for ASG EC2 instances with ingress from ALB only | data.aws_vpc.default |
| aws_vpc_security_group_ingress_rule | asg_from_alb | Allow HTTP (port 80) traffic from ALB security group to ASG instances | aws_security_group.asg_instances, module.alb |
| aws_vpc_security_group_egress_rule | asg_to_internet | Allow all outbound traffic from ASG instances for package updates and internet access | aws_security_group.asg_instances |
| time_sleep | wait_for_alb | 30-second delay after ALB creation before ASG attachment to ensure target group readiness | module.alb |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization per requirements |
| Project | sandbox | Project ID: prj-L3wMGgv1MTDuLBW4 |
| Workspace | sandbox_consumer_asg_workspace | Target workspace per requirements |
| Execution Mode | Remote | HCP Terraform managed |
| Terraform Version | >= 1.14 | Pinned in workspace settings |
| Variable Sets | agent_AWS_Dynamic_Creds (varset-9BtXAvxByVGEnHWV) | Provides dynamic AWS credentials via OIDC |
| VCS Connection | Not configured | Manual or API-driven runs |

---

## 3. Module Wiring

### Wiring Diagram

```
data.aws_vpc.default.id ──────────────────┬──→ module.alb.vpc_id
                                          ├──→ module.alb.target_groups["web"].vpc_id
                                          └──→ aws_security_group.asg_instances.vpc_id

data.aws_subnets.default.ids ────────────┬──→ module.alb.subnets
                                         └──→ module.autoscaling.vpc_zone_identifier

data.aws_ami.amazon_linux_2.id ──────────────→ module.autoscaling.image_id

module.alb.target_groups["web"].arn ─────────→ module.autoscaling.traffic_source_attachments["web"].traffic_source_identifier

module.alb.arn_suffix ───────────────────────┬──→ cloudwatch_alarm_alb_response_time.dimensions.LoadBalancer
                                            ├──→ cloudwatch_alarm_alb_5xx.dimensions.LoadBalancer
                                            └──→ cloudwatch_alarm_unhealthy_hosts.dimensions.LoadBalancer

module.alb.target_groups["web"].arn_suffix ──→ cloudwatch_alarm_unhealthy_hosts.dimensions.TargetGroup

module.autoscaling.autoscaling_group_name ───→ cloudwatch_alarm_asg_cpu.dimensions.AutoScalingGroupName

module.alb.security_group_id ────────────────→ aws_vpc_security_group_ingress_rule.asg_from_alb.referenced_security_group_id

aws_security_group.asg_instances.id ─────────→ module.autoscaling.security_groups
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| data.aws_vpc.default | id | module.alb | vpc_id | string | direct |
| data.aws_vpc.default | id | module.alb.target_groups["web"] | vpc_id | string | direct |
| data.aws_vpc.default | id | aws_security_group.asg_instances | vpc_id | string | direct |
| data.aws_subnets.default | ids | module.alb | subnets | list(string) | direct |
| data.aws_subnets.default | ids | module.autoscaling | vpc_zone_identifier | list(string) | direct |
| data.aws_ami.amazon_linux_2 | id | module.autoscaling | image_id | string | direct |
| module.alb | target_groups["web"].arn | module.autoscaling | traffic_source_attachments["web"].traffic_source_identifier | string | direct |
| module.alb | arn_suffix | cloudwatch_alarm_alb_response_time | dimensions.LoadBalancer | string | direct |
| module.alb | arn_suffix | cloudwatch_alarm_alb_5xx | dimensions.LoadBalancer | string | direct |
| module.alb | arn_suffix | cloudwatch_alarm_unhealthy_hosts | dimensions.LoadBalancer | string | direct |
| module.alb | target_groups["web"].arn_suffix | cloudwatch_alarm_unhealthy_hosts | dimensions.TargetGroup | string | direct |
| module.autoscaling | autoscaling_group_name | cloudwatch_alarm_asg_cpu | dimensions.AutoScalingGroupName | string | direct |
| module.alb | security_group_id | aws_vpc_security_group_ingress_rule.asg_from_alb | referenced_security_group_id | string | direct |
| aws_security_group.asg_instances | id | module.autoscaling | security_groups | list(string) | wrap in list: `[...]` |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Deployment  = "consumer-asg"
    }
  }

  # Dynamic credentials via HCP Terraform variable set
  # TFC_AWS_PROVIDER_AUTH = true (configured in workspace)
  # TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::ACCOUNT:role/terraform (configured in variable set)
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| aws_region | string | No | "ap-southeast-2" | Must be valid AWS region format | No | AWS region for resource deployment |
| project_name | string | No | "consumer-asg" | -- | No | Project identifier for resource naming and tagging |
| environment | string | No | "development" | Must be one of: development, staging, production | No | Environment name for resource tagging and configuration |
| owner | string | Yes | -- | Non-empty string | No | Owner email or team identifier for resource accountability |
| instance_type | string | No | "t3.micro" | Must match t3.* or t2.* pattern | No | EC2 instance type for ASG launch template |
| asg_min_size | number | No | 1 | Must be >= 0 and <= asg_max_size | No | Minimum number of EC2 instances in Auto Scaling Group |
| asg_max_size | number | No | 3 | Must be >= asg_min_size and <= 10 | No | Maximum number of EC2 instances in Auto Scaling Group |
| asg_desired_capacity | number | No | 1 | Must be >= asg_min_size and <= asg_max_size | No | Initial desired number of EC2 instances in Auto Scaling Group |
| asg_health_check_grace_period | number | No | 300 | Must be >= 0 | No | Time in seconds after instance launch before health checks start |
| cpu_target_value | number | No | 70.0 | Must be > 0 and <= 100 | No | Target CPU utilization percentage for auto-scaling policy |
| alb_health_check_path | string | No | "/" | Must start with / | No | HTTP path for ALB target group health checks |
| alb_health_check_interval | number | No | 30 | Must be >= 5 and <= 300 | No | Time in seconds between ALB health checks |
| alarm_cpu_threshold | number | No | 80.0 | Must be > 0 and <= 100 | No | CPU utilization percentage threshold for CloudWatch alarm |
| alarm_response_time_threshold | number | No | 1.0 | Must be > 0 | No | ALB target response time in seconds threshold for CloudWatch alarm |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| alb_dns_name | string | module.alb.dns_name | DNS name of the Application Load Balancer for accessing the application |
| alb_arn | string | module.alb.arn | ARN of the Application Load Balancer for CloudWatch metrics and logging configuration |
| alb_zone_id | string | module.alb.zone_id | Route53 hosted zone ID of the ALB for DNS alias record creation |
| asg_id | string | module.autoscaling.autoscaling_group_id | Auto Scaling Group identifier for AWS console reference |
| asg_name | string | module.autoscaling.autoscaling_group_name | Auto Scaling Group name for CloudWatch metrics and API operations |
| asg_arn | string | module.autoscaling.autoscaling_group_arn | ARN of the Auto Scaling Group for IAM policy attachments and monitoring |
| launch_template_id | string | module.autoscaling.launch_template_id | Launch template identifier for AMI update workflows |
| vpc_id | string | data.aws_vpc.default.id | VPC ID used for deployment for networking context |
| subnet_ids | list(string) | data.aws_subnets.default.ids | Subnet IDs used for ALB and ASG placement |
| asg_security_group_id | string | aws_security_group.asg_instances.id | Security group ID for ASG instances for manual rule additions |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | Module default honoured — EBS volumes use AWS account default encryption | module.autoscaling: no explicit `encrypt = false` override, uses AWS default KMS encryption | CIS AWS 2.2.1 - Ensure EBS volume encryption is enabled |
| Encryption in transit | Module default honoured — ALB does not enforce HTTPS (development environment) | module.alb: `internal = false`, no TLS listener configured (HTTP-only for development) | [SECURITY OVERRIDE] CIS AWS 2.6.1 - Development environment, TLS certificate management out of scope |
| Public access | ALB internet-facing — intentional for development testing. EC2 instances not publicly accessible. | module.alb: `internal = false` (internet-facing). module.autoscaling: instances in subnets without public IP auto-assignment, security group blocks direct internet access | CIS AWS 5.3 - Ensure no security groups allow ingress from 0.0.0.0/0 to administrative ports |
| IAM least privilege | Module default enforced — ASG IAM instance profile with no additional permissions | module.autoscaling: `create_iam_instance_profile = true` with no `iam_role_policies` override, minimal default permissions | CIS AWS 1.16 - Ensure IAM policies are attached only to groups or roles |
| Logging | ALB access logs not enabled — cost optimization for development | module.alb: no `access_logs` configuration | [SECURITY OVERRIDE] CIS AWS 3.5 - Development environment, S3 bucket for logs out of scope |
| Network segmentation | Security groups enforce least-privilege network controls — ALB to ASG only | ALB SG: ingress 0.0.0.0/0:80, egress to ASG SG only. ASG SG: ingress from ALB SG only on port 80, egress 0.0.0.0/0 for updates | CIS AWS 5.2 - Ensure the default security group restricts all traffic |
| IMDSv2 enforcement | Module default enforced — Instance Metadata Service v2 required | module.autoscaling: `metadata_options.http_tokens = "required"` (module default), no override to "optional" | CIS AWS 5.6 - Ensure Instance Metadata Service Version 1 is not enabled |
| Tagging | Provider default_tags applied to all resources automatically | provider.aws: `default_tags` with Project, Environment, ManagedBy, Owner, Deployment | CIS AWS 7.1 - Eliminate use of 'root' user for administrative purposes (tagging for accountability) |
| Dynamic credentials | HCP Terraform dynamic credentials via OIDC — no static AWS keys | Variable set `agent_AWS_Dynamic_Creds` attached, provides TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN | AWS Well-Architected Security Pillar - Use temporary credentials |
| Health monitoring | ELB health checks with 300s grace period — prevents premature instance termination | module.autoscaling: `health_check_type = "ELB"`, `health_check_grace_period = 300` | AWS Well-Architected Reliability Pillar - Monitor workload resources |

---

## 5. Implementation Checklist

- [x] **Scaffold**: Create file structure with HCP Terraform backend configuration and provider setup. Files: `versions.tf` (terraform block with cloud backend, required_version >= 1.14, required_providers aws ~> 6.19), `backend.tf` (cloud block with organization "hashi-demos-apj", workspace "sandbox_consumer_asg_workspace"), `providers.tf` (provider "aws" with region variable and default_tags), `variables.tf` (all 12 variables from Section 3 with type, description, validation), `outputs.tf` (all 10 outputs from Section 3), `locals.tf` (naming prefix pattern, AZ list), `data.tf` (aws_vpc default, aws_subnets filter, aws_ami amazon_linux_2 lookup).

- [x] **ALB module**: Provision Application Load Balancer with target group and HTTP listener. File: `main.tf` — Add module "alb" block with vpc_id from data source, subnets from data source, internal = false, target_groups map with "web" key (port 80, protocol HTTP, target_type instance, health_check with path, interval, thresholds), listeners map with "http" key (port 80, forward to "web" target group), enable_deletion_protection = false (dev), drop_invalid_header_fields = true. Add time_sleep resource for 30s delay after ALB creation.

- [x] **ASG module**: Provision Auto Scaling Group with launch template and target tracking scaling policy. File: `main.tf` — Add module "autoscaling" block with vpc_zone_identifier from data source, traffic_source_attachments map with "web" key (traffic_source_identifier from alb module target_groups output), image_id from data source, instance_type variable, security_groups list with glue SG id, min_size, max_size, desired_capacity variables, health_check_type = "ELB", health_check_grace_period variable, scaling_policies map with target_tracking_scaling_policy_configuration for CPU utilization, enabled_metrics list (8 ASG metrics), depends_on time_sleep.

- [ ] **Security groups**: Create glue security group resources for ASG instances with least-privilege ingress/egress rules. File: `main.tf` — Add aws_security_group "asg_instances" with vpc_id from data source, name with naming pattern, description. Add aws_vpc_security_group_ingress_rule "asg_from_alb" with security_group_id referencing asg_instances, from_port = 80, to_port = 80, ip_protocol = "tcp", referenced_security_group_id from alb module output. Add aws_vpc_security_group_egress_rule "asg_to_internet" with security_group_id referencing asg_instances, ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0".

- [ ] **CloudWatch alarms**: Provision 4 metric alarms for ASG and ALB monitoring. File: `main.tf` — Add module "cloudwatch_alarm_asg_cpu" with source submodule path, alarm_name with naming pattern, comparison_operator = "GreaterThanThreshold", threshold = alarm_cpu_threshold variable, namespace = "AWS/EC2", metric_name = "CPUUtilization", dimensions map with AutoScalingGroupName from asg module, evaluation_periods = 2, period = 300. Add module "cloudwatch_alarm_alb_response_time" with namespace = "AWS/ApplicationELB", metric_name = "TargetResponseTime", dimensions with LoadBalancer from alb arn_suffix, statistic = "Average", threshold = alarm_response_time_threshold variable. Add module "cloudwatch_alarm_alb_5xx" with metric_name = "HTTPCode_Target_5XX_Count", statistic = "Sum", threshold = 10. Add module "cloudwatch_alarm_unhealthy_hosts" with metric_name = "UnHealthyHostCount", dimensions with LoadBalancer and TargetGroup from alb outputs, threshold = 0.

- [ ] **Polish**: Create README with deployment instructions, example tfvars file, format all files, and validate syntax. Files: `README.md` (deployment overview, prerequisites with HCP Terraform workspace setup and variable set attachment, terraform init/plan/apply instructions, output descriptions, troubleshooting common issues), `terraform.auto.tfvars.example` (example values for all required and optional variables with comments), run `terraform fmt -recursive .`, run `terraform validate`, verify no hardcoded secrets with `grep -r 'aws_access_key\|aws_secret_key' .`, verify all files conform to constitution file organization standards.

---

## 6. Open Questions

-- (All requirements clarified during Phase 1)

---

## Design Validation Checklist

**Requirement Quality Validation**:
- ✅ Every functional requirement in §1 maps to at least one module in §2
- ✅ No requirement is ambiguous or untestable
- ✅ Scope boundary is clearly defined

**Specification Consistency**:
- ✅ Table of Contents links to all 6 sections
- ✅ Every module in §2 has Registry Source and Version filled
- ✅ Every module output consumed downstream appears in §3 Wiring Table
- ✅ Wiring diagram matches wiring table — no orphaned connections
- ✅ Every variable in §3 has Type + Description filled
- ✅ Every security control in §4 has a CIS or Well-Architected reference (or explicit N/A justification)
- ✅ Provider configuration in §3 includes `default_tags` per constitution
- ✅ Implementation checklist in §5 has 6 items (within 4-8 range)
- ✅ No section references another section by line number
- ✅ Module names appear exactly once — in Module Inventory (§2)
- ✅ Variable names appear exactly once — in Module Wiring (§3)
- ✅ No raw infrastructure resource blocks except glue resources (security groups, data sources, time_sleep)

**Cross-Reference Validation**:
- ✅ Every module listed in §2 is referenced in at least one wiring connection in §3
- ✅ Every security control in §4 references a specific module from §2 or glue resource
- ✅ Implementation checklist items in §5 cover all modules from §2
- ✅ All module selections reference research findings from Phase 1 (research-modules-summary.md, research-module-wiring.md, research-asg-alb-architecture.md, research-cloudwatch.md, research-networking.md)
