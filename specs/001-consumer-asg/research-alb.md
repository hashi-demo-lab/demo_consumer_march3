## Research: What private registry modules are available for Application Load Balancers?

### Decision

Use `hashi-demos-apj/alb/aws` v10.1.0 — provides complete ALB infrastructure with target groups, listeners, listener rules, security groups, and Route53 integration with secure defaults.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0
  - **Purpose**: Provisions Application Load Balancers with target groups, listeners, listener rules, and Route53 records
  - **Key Inputs**: 
    - `name` (string) - Load balancer name (max 32 chars)
    - `internal` (bool) - Internal or internet-facing (default: false)
    - `vpc_id` (string) - VPC ID for target groups
    - `subnets` (list(string)) - Subnet IDs for ALB placement (minimum 2 AZs)
    - `security_groups` (list(string)) - Security group IDs (optional, creates default)
    - `enable_deletion_protection` (bool) - Deletion protection (default: true)
    - `drop_invalid_header_fields` (bool) - Drop invalid HTTP headers (default: true)
    - `enable_cross_zone_load_balancing` (bool) - Cross-zone LB (default: true)
    - `access_logs` (object) - S3 access logging configuration
      - `bucket` (string) - S3 bucket name
      - `enabled` (bool) - Enable logging (default: true)
      - `prefix` (string) - S3 key prefix
    - `target_groups` (map(object)) - Target group definitions
      - `name` (string) - Target group name
      - `port` (number) - Target port
      - `protocol` (string) - HTTP, HTTPS, TCP, etc.
      - `target_type` (string) - "instance", "ip", or "lambda"
      - `vpc_id` (string) - VPC ID for target group
      - `health_check` (object) - Health check configuration
        - `path` (string) - Health check path (e.g., "/health")
        - `interval` (number) - Check interval in seconds
        - `timeout` (number) - Check timeout in seconds
        - `healthy_threshold` (number) - Consecutive successes to mark healthy
        - `unhealthy_threshold` (number) - Consecutive failures to mark unhealthy
        - `matcher` (string) - HTTP status code matcher (e.g., "200")
      - `deregistration_delay` (number) - Connection draining delay
      - `stickiness` (object) - Session stickiness config
    - `listeners` (map(object)) - Listener configurations
      - `port` (number) - Listener port
      - `protocol` (string) - HTTP, HTTPS
      - `forward` (object) - Forward action to target group
    - `listener_rules` (map(object)) - Routing rules
    - `route53_records` (map(object)) - DNS record creation
  - **Key Outputs**: 
    - `id` (string) - Load balancer ID/ARN
    - `arn` (string) - Load balancer ARN
    - `arn_suffix` (string) - ARN suffix for CloudWatch metrics (⚠️ CRITICAL for monitoring)
    - `dns_name` (string) - ALB DNS name
    - `zone_id` (string) - Route53 zone ID for alias records
    - `target_groups` (map(object)) - Target group details map
      - Each entry contains: `arn` (string), `id` (string), `name` (string), `arn_suffix` (string)
    - `listeners` (map(object)) - Listener details
    - `listener_rules` (map(object)) - Listener rule details
    - `security_group_id` (string) - Created security group ID
    - `security_group_arn` (string) - Security group ARN
    - `route53_records` (map(object)) - Created Route53 records
  - **Secure Defaults**: 
    - Deletion protection enabled (prevents accidental deletion)
    - Invalid HTTP header dropping enabled (security hardening)
    - Cross-zone load balancing enabled (high availability)
    - Creates security group automatically with best practices
    - Supports WAF integration via `web_acl_arn`
  - **Wiring Considerations**: 
    - **Input from VPC**: 
      - `vpc_id = module.vpc.vpc_id` (string)
      - `subnets = module.vpc.public_subnets` (list(string)) for internet-facing
      - `subnets = module.vpc.private_subnets` (list(string)) for internal
    - **Input from Security Group**: 
      - `security_groups = [module.alb_sg.security_group_id]` (list(string))
      - If not provided, module creates security group automatically
    - **Output to ASG**: 
      - `target_groups["web"].arn` (string) → `asg.target_group_arns` input (list)
      - ⚠️ Must extract `.arn` attribute from target_groups map: `[module.alb.target_groups["web"].arn]`
    - **Output to CloudWatch**: 
      - `arn_suffix` (string) → alarm dimensions `{LoadBalancer = module.alb.arn_suffix}`
      - Example: `"app/my-alb/50dc6c495c0c9188"`
      - Used for namespace `"AWS/ApplicationELB"`
    - **Type Compatibility**: All inputs/outputs verified
      - VPC `vpc_id` is string ✅
      - VPC `public_subnets` is list(string) ✅
      - Target groups map contains string attributes ✅

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 — VPC with public/private subnets
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — Custom security groups (optional)
  - `app.terraform.io/hashi-demos-apj/route53/aws` — Route53 DNS records (alternative to built-in)
  - `app.terraform.io/hashi-demos-apj/acm/aws` — ACM certificates for HTTPS listeners

- **Glue Resources Needed**: 
  - `data "aws_acm_certificate"` - For HTTPS listeners
  - `aws_sns_topic` - For CloudWatch alarm notifications
  - No additional glue for basic HTTP setup

### Rationale

The `alb` module is the only ALB module in the private registry and provides comprehensive functionality:

1. **Complete ALB feature set** — target groups, listeners, rules, Route53 integration
2. **Target group flexibility** — supports instance, IP, and Lambda targets
3. **Health check configuration** — full control over health check parameters
4. **Security hardening** — deletion protection, header validation, automatic security groups
5. **CloudWatch integration** — outputs `arn_suffix` for metric namespace dimensions
6. **Multi-AZ support** — requires 2+ subnets across AZs for high availability
7. **Access logging** — S3 access logs for audit trail
8. **Route53 integration** — automatic DNS record creation

Module created recently (2025-11-03) with provider constraint `>= 6.19`, indicating active maintenance and use of latest AWS provider features.

The target groups output as a map allows multiple target groups per ALB, enabling blue/green deployments or multi-application hosting.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/alb/aws` | Organization policy requires private registry modules |
| Raw `aws_lb` + `aws_lb_target_group` | Consumer constitution prohibits raw resources |
| `aws_elb` (Classic Load Balancer) | Deprecated, ALB is modern replacement with more features |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj/alb/aws`
- MCP tool: `get_private_module_details` output for version 10.1.0
- VCS repository: `https://github.com/hashi-demo-lab/terraform-aws-alb`
- AWS docs: Application Load Balancer documentation
- AWS docs: Target group health checks
- AWS docs: CloudWatch metrics for ALB (`AWS/ApplicationELB` namespace)
