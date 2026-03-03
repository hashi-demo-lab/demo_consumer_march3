## Research: What private registry modules are available for networking infrastructure (VPC, Security Groups)?

### Decision

Use `hashi-demos-apj/vpc/aws` v6.5.0 for VPC infrastructure and `hashi-demos-apj/security-group/aws` v5.3.1 for security groups — both provide comprehensive networking foundation with secure defaults and compatible outputs for ALB+ASG composition.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0
  - **Purpose**: Provisions VPC with public/private/database subnets, NAT gateways, internet gateway, route tables, and VPC Flow Logs
  - **Key Inputs**: 
    - `name` (string) - VPC name
    - `cidr` (string) - VPC CIDR block (e.g., "10.0.0.0/16")
    - `azs` (list(string)) - Availability zones (e.g., ["us-east-1a", "us-east-1b"])
    - `public_subnets` (list(string)) - Public subnet CIDRs
    - `private_subnets` (list(string)) - Private subnet CIDRs
    - `database_subnets` (list(string)) - Database subnet CIDRs
    - `enable_nat_gateway` (bool) - Enable NAT gateway for private subnets
    - `single_nat_gateway` (bool) - Single NAT (cost savings) vs one per AZ (HA)
    - `enable_dns_hostnames` (bool) - Enable DNS hostnames
    - `enable_dns_support` (bool) - Enable DNS support
    - `enable_flow_log` (bool) - Enable VPC Flow Logs
    - `flow_log_destination_type` (string) - "cloud-watch-logs" or "s3"
  - **Key Outputs**: 
    - `vpc_id` (string) - VPC identifier ⚠️ CRITICAL for all modules
    - `vpc_cidr_block` (string) - VPC CIDR block
    - `public_subnets` (list(string)) - Public subnet IDs → ALB placement
    - `private_subnets` (list(string)) - Private subnet IDs → ASG placement
    - `database_subnets` (list(string)) - Database subnet IDs → RDS placement
    - `natgw_ids` (list(string)) - NAT Gateway IDs
    - `igw_id` (string) - Internet Gateway ID
    - `public_route_table_ids` (list(string)) - Public route table IDs
    - `private_route_table_ids` (list(string)) - Private route table IDs
    - `vpc_owner_id` (string) - AWS account ID
  - **Secure Defaults**: 
    - DNS hostnames and support enabled by default
    - VPC Flow Logs support for network monitoring
    - NAT Gateway support for private subnet egress
  - **Wiring Considerations**: 
    - **Output to ALB (internet-facing)**: `public_subnets` (list(string)) → `alb.subnets`
    - **Output to ALB (internal)**: `private_subnets` (list(string)) → `alb.subnets`
    - **Output to ASG**: `private_subnets` (list(string)) → `asg.vpc_zone_identifier`
    - **Output to Security Groups**: `vpc_id` (string) → `security_group.vpc_id`
    - **Output to ALB Target Groups**: `vpc_id` (string) → `alb.target_groups[*].vpc_id`
    - **Type Compatibility**: All outputs verified
      - `vpc_id` is string ✅
      - `public_subnets` is list(string) ✅
      - `private_subnets` is list(string) ✅

- **Primary Module**: `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1
  - **Purpose**: Provisions AWS security groups with ingress/egress rules
  - **Key Inputs**: 
    - `name` (string) - Security group name
    - `description` (string) - Security group description
    - `vpc_id` (string) - VPC ID (required)
    - `ingress_rules` (list(string)) - Predefined rule names (e.g., "http-80-tcp", "https-443-tcp")
    - `ingress_with_cidr_blocks` (list(object)) - Ingress rules with CIDR blocks
      - `from_port`, `to_port`, `protocol`, `cidr_blocks`, `description`
    - `ingress_with_source_security_group_id` (list(object)) - Ingress from other SGs
      - `from_port`, `to_port`, `protocol`, `source_security_group_id`, `description`
    - `ingress_with_self` (list(object)) - Ingress from same security group
    - `egress_rules` (list(string)) - Predefined egress rule names
    - `egress_with_cidr_blocks` (list(object)) - Egress rules with CIDR blocks
    - `egress_with_source_security_group_id` (list(object)) - Egress to other SGs
    - `tags` (map(string)) - Tags
  - **Key Outputs**: 
    - `security_group_id` (string) - Security group ID ⚠️ CRITICAL for ASG/ALB
    - `security_group_arn` (string) - Security group ARN
    - `security_group_name` (string) - Security group name
    - `security_group_vpc_id` (string) - VPC ID
  - **Secure Defaults**: 
    - No ingress/egress rules by default (explicit configuration required)
    - Supports rule description for documentation
  - **Wiring Considerations**: 
    - **Input from VPC**: `vpc_id = module.vpc.vpc_id` (string)
    - **Output to ALB**: `security_group_id` (string) → `alb.security_groups` (list)
    - **Output to ASG**: `security_group_id` (string) → `asg.security_groups` (list)
    - **Cross-SG References**: ALB SG ID → ASG SG ingress rule `source_security_group_id`
    - **Type Compatibility**: All inputs/outputs verified
      - VPC `vpc_id` is string ✅
      - SG `security_group_id` is string ✅

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/kms/aws` v4.6.0 — KMS keys for VPC Flow Log encryption
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` — S3 bucket for VPC Flow Logs

- **Glue Resources Needed**: 
  - `data "aws_availability_zones"` - To dynamically determine available AZs
  - `aws_eip` - For NAT Gateway Elastic IPs (if not using single_nat_gateway)
  - No glue for basic VPC+SG setup

### Rationale

**VPC Module** (`vpc/aws` v6.5.0):
1. **Multi-subnet support** — public, private, database subnet tiers
2. **NAT Gateway flexibility** — single (cost) vs per-AZ (HA)
3. **Internet Gateway** — automatic IGW provisioning
4. **Route table management** — separate public/private route tables
5. **VPC Flow Logs** — network traffic monitoring capability
6. **Multi-AZ support** — distributes subnets across AZs for HA
7. **Compatible outputs** — `vpc_id`, `public_subnets`, `private_subnets` match ALB/ASG input types

**Security Group Module** (`security-group/aws` v5.3.1):
1. **Flexible rule definition** — CIDR blocks, SG references, self-referencing
2. **Predefined rule shortcuts** — common rules like "http-80-tcp"
3. **Cross-SG references** — ALB → ASG security group chaining
4. **Rule descriptions** — documentation built into rules
5. **Compatible outputs** — `security_group_id` matches ALB/ASG input types

Both modules created recently (2025-10-26 and 2025-11-03) with modern provider constraints, indicating active maintenance.

### Architecture Pattern

**Recommended VPC Design for ASG+ALB**:
```
VPC (10.0.0.0/16)
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
│   ├── Internet Gateway → 0.0.0.0/0
│   └── ALB (internet-facing)
└── Private Subnets (10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24)
    ├── NAT Gateway → 0.0.0.0/0 (for egress)
    └── ASG instances
```

**Recommended Security Group Design**:
```
ALB Security Group
├── Ingress: 0.0.0.0/0:80 (HTTP)
├── Ingress: 0.0.0.0/0:443 (HTTPS)
└── Egress: ASG SG:8080 (application port)

ASG Security Group
├── Ingress: ALB SG:8080 (application port)
└── Egress: 0.0.0.0/0:443 (HTTPS for external API calls)
```

**High Availability Considerations**:
- Minimum 2 AZs required for ALB
- Recommended 3 AZs for production
- Use `single_nat_gateway = false` for HA (one NAT per AZ)
- ASG spans all private subnets for even distribution

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/vpc/aws` | Organization policy requires private registry modules |
| Raw `aws_vpc` + `aws_subnet` | Consumer constitution prohibits raw resources |
| Single public/private subnet | Multi-AZ required for ALB, HA requires multiple subnets |
| Security groups in ALB/ASG modules | Separate SG module allows reusability and cross-SG references |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj/vpc/aws`
- Private registry: `app.terraform.io/hashi-demos-apj/security-group/aws`
- MCP tool: `get_private_module_details` output for both modules
- VCS repositories: 
  - `https://github.com/hashi-demo-lab/terraform-aws-vpc`
  - `https://github.com/hashi-demo-lab/terraform-aws-security-group`
- AWS docs: VPC with Public and Private Subnets (NAT)
- AWS docs: VPC Flow Logs
- AWS docs: Security Groups for Your VPC
- AWS Well-Architected Framework: Network design patterns
