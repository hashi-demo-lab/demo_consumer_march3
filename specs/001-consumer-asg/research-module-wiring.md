## Research: Module wiring patterns for composing ASG + ALB from private registry modules

### Decision

Use `traffic_source_attachments` on the autoscaling module to connect ASG instances to ALB target groups — this is the modern, provider-native approach that supports multiple target groups and proper lifecycle management.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
  - **Purpose**: AWS Auto Scaling Group with launch template, IAM roles, scaling policies, and traffic source attachments
  - **Key Inputs**: 
    - `vpc_zone_identifier` (list(string)) — subnet IDs for ASG instances
    - `security_groups` (list(string)) — security group IDs for instances
    - `traffic_source_attachments` (map(object)) — connects to ALB target groups
    - `min_size`, `max_size`, `desired_capacity` (number) — scaling configuration
    - `image_id` (string) — AMI ID for instances
  - **Key Outputs**: 
    - `autoscaling_group_id` (string)
    - `autoscaling_group_name` (string)
    - `autoscaling_group_arn` (string)
    - `launch_template_id` (string)
  - **Secure Defaults**: IMDSv2 required (`http_tokens = "required"`), detailed monitoring enabled

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0 — Application Load Balancer with target groups, listeners, and security groups
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — Security group management (optional, ALB module creates its own)
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 — VPC infrastructure (optional, can use default VPC)

- **Glue Resources Needed**: 
  - `data "aws_vpc"` — to reference default VPC
  - `data "aws_subnets"` — to query subnet IDs from default VPC
  - No `random_id` or `null_resource` needed for basic wiring

- **Wiring Considerations**:
  - ALB module outputs `target_groups` as a map with ARNs at `target_groups["key"].arn`
  - ASG module expects `traffic_source_attachments` as map of objects with `traffic_source_identifier` (the ARN)
  - Type compatibility: Both VPC data sources and module inputs use `list(string)` for subnet IDs — direct pass-through works
  - Security group wiring: ALB module outputs `security_group_id`, ASG module accepts `security_groups = [alb_sg_id]` for ingress rules
  - VPC ID flows: ALB needs `vpc_id`, target groups need `vpc_id`, security groups need `vpc_id` — all from data source

### Rationale

The `traffic_source_attachments` input on the autoscaling module is the recommended approach for connecting ASG to ALB target groups (per AWS provider >= 6.12). It replaces the legacy `target_group_arns` attribute and provides:

1. **Better lifecycle management**: Attachments are tracked separately, reducing conflicts
2. **Multiple target group support**: Native map structure supports multiple ALB/NLB connections
3. **Type safety**: Uses `traffic_source_identifier` (string) which matches target group ARN output type

**Evidence from module schemas**:
- ALB module outputs: `target_groups` map includes `arn` attribute (type: string)
- ASG module input: `traffic_source_attachments` expects map of objects with `traffic_source_identifier` (string)
- Direct reference pattern: `alb_module.target_groups["web"].arn` → `asg_module.traffic_source_attachments["web"].traffic_source_identifier`

**VPC/Subnet data flow**:
- `data "aws_vpc"` with `default = true` returns VPC ID as string
- `data "aws_subnets"` with VPC ID filter returns `ids` as list(string)
- Both ALB (`subnets`) and ASG (`vpc_zone_identifier`) accept `list(string)` — no conversion needed
- Type compatibility verified: list vs set concerns don't apply here (data sources return lists)

**Security group wiring**:
- ALB module creates its own security group and outputs `security_group_id` (string)
- ASG instances need to allow traffic from ALB: create separate security group with ingress rule referencing ALB SG
- Pattern: ASG security group ingress rule with `source_security_group_id = alb_module.security_group_id`

**Dynamic credentials for HCP Terraform**:
- Set `TFC_AWS_PROVIDER_AUTH = true` and `TFC_AWS_RUN_ROLE_ARN = <role_arn>` in workspace variables
- Use `cloud {}` backend block with `organization` and `workspaces` configuration
- Variable set `agent_AWS_Dynamic_Creds` exists in hashi-demos-apj org (ID: varset-9BtXAvxByVGEnHWV) with 3 variables configured
- Attach this variable set to the workspace for automatic AWS authentication

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Legacy `target_group_arns` on ASG | Deprecated in favor of `traffic_source_attachments` in AWS provider >= 6.12 |
| Direct `target_group_arns` list | Module uses modern `traffic_source_attachments` map structure — better for multiple targets |
| Hardcode VPC/subnet IDs | Not portable across environments; data sources provide runtime discovery |
| Use `toset()` for subnet IDs | Unnecessary — both data source and module inputs use `list(string)` natively |
| Create VPC with vpc module | Overkill for initial implementation — default VPC simplifies deployment |
| Static AWS credentials | Organization uses dynamic credentials (OIDC) — variable set already configured |

### Sources

- Private registry: `hashi-demos-apj/autoscaling/aws` v9.0.2 schema
- Private registry: `hashi-demos-apj/alb/aws` v10.1.0 schema
- AWS provider docs: `aws_vpc` data source (providerDocID: 11552056)
- AWS provider docs: `aws_subnets` data source (providerDocID: 11552048)
- HCP Terraform docs: Dynamic provider credentials for AWS (https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- Variable set: `agent_AWS_Dynamic_Creds` (varset-9BtXAvxByVGEnHWV) in hashi-demos-apj org
- Public registry pattern: cloudposse/ecs-web-app/aws — demonstrates `traffic_source_attachments` usage with ALB

### Practical Wiring Examples

#### 1. ALB Target Group ARN to ASG Connection

```hcl
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "10.1.0"

  vpc_id  = data.aws_vpc.default.id
  subnets = data.aws_subnets.default.ids

  target_groups = {
    web = {
      name        = "asg-web-tg"
      port        = 80
      protocol    = "HTTP"
      target_type = "instance"
      vpc_id      = data.aws_vpc.default.id
      health_check = {
        enabled  = true
        path     = "/"
        interval = 30
      }
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

module "asg" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "9.0.2"

  vpc_zone_identifier = data.aws_subnets.default.ids
  security_groups     = [aws_security_group.asg_instances.id]

  # Wiring: Connect ASG to ALB target group
  traffic_source_attachments = {
    web = {
      traffic_source_identifier = module.alb.target_groups["web"].arn
      traffic_source_type       = "elbv2"  # default, can omit
    }
  }

  min_size         = 2
  max_size         = 4
  desired_capacity = 2
}
```

**Output type verification**:
- `module.alb.target_groups["web"].arn` → type: `string` (ARN of target group)
- `traffic_source_identifier` expects → type: `string` ✅ Compatible

#### 2. VPC/Subnet Data Flow with Default VPC

```hcl
# Query default VPC
data "aws_vpc" "default" {
  default = true
}

# Query all subnets in default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Output types:
# - data.aws_vpc.default.id → string
# - data.aws_subnets.default.ids → list(string)

module "alb" {
  # ...
  vpc_id  = data.aws_vpc.default.id      # string → string ✅
  subnets = data.aws_subnets.default.ids # list(string) → list(string) ✅
}

module "asg" {
  # ...
  vpc_zone_identifier = data.aws_subnets.default.ids # list(string) → list(string) ✅
}
```

**Type compatibility verified**: No conversion needed between data sources and module inputs.

#### 3. Security Group Wiring Between ALB and ASG

```hcl
# ALB creates its own security group automatically
module "alb" {
  # ...
  create_security_group = true  # default
  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP from internet"
    }
  }
  security_group_egress_rules = {
    all_instances = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = aws_security_group.asg_instances.id
      description                  = "Allow traffic to ASG instances"
    }
  }
}

# ASG instances security group - allow traffic from ALB
resource "aws_security_group" "asg_instances" {
  name        = "asg-instances"
  description = "Security group for ASG instances"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.asg_instances.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
  description                  = "Allow HTTP from ALB"
}

resource "aws_vpc_security_group_egress_rule" "to_internet" {
  security_group_id = aws_security_group.asg_instances.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all outbound traffic"
}
```

**Wiring pattern**: ALB SG → ASG instances via security group references (not CIDR blocks).

#### 4. HCP Terraform Workspace Configuration

**terraform block with cloud backend**:
```hcl
terraform {
  required_version = ">= 1.6"

  cloud {
    organization = "hashi-demos-apj"
    workspaces {
      name = "consumer-asg-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.19"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  # Dynamic credentials configured via workspace variables
  # No access_key/secret_key needed
}
```

**Workspace variable configuration** (via UI or API):
1. **Attach variable set**: `agent_AWS_Dynamic_Creds` (varset-9BtXAvxByVGEnHWV)
   - Already contains 3 variables for dynamic credentials
   - Likely includes: `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`, audience config

2. **Additional workspace variables** (if needed):
   - `TFC_AWS_PROVIDER_AUTH` = `true` (env var)
   - `TFC_AWS_RUN_ROLE_ARN` = `arn:aws:iam::ACCOUNT_ID:role/terraform-role` (env var)
   - `AWS_REGION` = `us-west-2` (env var) — or use provider config

**Verification**: Variable set contains 3 variables already configured for the organization.

### Type Compatibility Summary

| Source | Type | Destination | Type | Compatible? |
|--------|------|-------------|------|-------------|
| `data.aws_vpc.default.id` | `string` | ALB `vpc_id` | `string` | ✅ Yes |
| `data.aws_subnets.default.ids` | `list(string)` | ALB `subnets` | `list(string)` | ✅ Yes |
| `data.aws_subnets.default.ids` | `list(string)` | ASG `vpc_zone_identifier` | `list(string)` | ✅ Yes |
| ALB `target_groups["web"].arn` | `string` | ASG `traffic_source_attachments["web"].traffic_source_identifier` | `string` | ✅ Yes |
| ALB `security_group_id` | `string` | ASG SG ingress `referenced_security_group_id` | `string` | ✅ Yes |

**Conclusion**: No type conversions (e.g., `toset()`, `tolist()`) needed for standard wiring patterns with these modules.
