## Research: What private registry modules are available for CloudWatch monitoring?

### Decision

Use `hashi-demos-apj/cloudwatch/aws` v5.7.2 with submodules `metric-alarm` and `metric-alarms-by-multiple-dimensions` — provides comprehensive CloudWatch resources including alarms, log groups, metric filters, dashboards, and CIS benchmark alarms.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2
  - **Purpose**: Provisions CloudWatch log groups, metric filters, alarms, dashboards, composite alarms, and log streams
  - **Submodules Available**:
    - `modules/metric-alarm` - Individual CloudWatch alarms
    - `modules/metric-alarms-by-multiple-dimensions` - Batch alarm creation (e.g., multiple Lambda functions)
    - `modules/log-group` - CloudWatch log groups with retention
    - `modules/log-stream` - Log streams
    - `modules/log-metric-filter` - Extract metrics from log patterns
    - `modules/cis-alarms` - CIS AWS Foundations benchmark alarms
    - `modules/composite-alarm` - Composite alarms with alarm rule logic
    - `modules/query-definition` - CloudWatch Insights queries
    - `modules/metric-stream` - Metric streaming to Kinesis/Firehose
    - `modules/log-subscription-filter` - Log subscription filters
    - `modules/log-data-protection-policy` - PII redaction policies
    - `modules/log-account-policy` - Account-level data protection
    - `modules/log-anomaly-detector` - Anomaly detection for logs
  
  - **Key Inputs (metric-alarm submodule)**: 
    - `alarm_name` (string) - Alarm identifier
    - `alarm_description` (string) - Alarm description
    - `comparison_operator` (string) - "GreaterThanThreshold", "LessThanThreshold", etc.
    - `evaluation_periods` (number) - Number of periods to evaluate
    - `threshold` (number) - Alarm threshold value
    - `namespace` (string) - CloudWatch metric namespace
      - For ALB: `"AWS/ApplicationELB"`
      - For ASG/EC2: `"AWS/EC2"`
      - For custom: `"Custom/MyApp"`
    - `metric_name` (string) - Metric name
      - ALB: `"TargetResponseTime"`, `"HTTPCode_Target_5XX_Count"`, `"HealthyHostCount"`, `"UnHealthyHostCount"`
      - EC2: `"CPUUtilization"`, `"NetworkIn"`, `"NetworkOut"`, `"StatusCheckFailed"`
    - `statistic` (string) - "Average", "Sum", "Maximum", "Minimum", "SampleCount"
    - `period` (number) - Metric evaluation period in seconds (60, 300, etc.)
    - `dimensions` (map(string)) - Metric dimensions
      - For ALB: `{LoadBalancer = "app/my-alb/50dc6c495c0c9188"}` (use `arn_suffix`)
      - For ASG: `{AutoScalingGroupName = "my-app-asg"}`
      - For EC2: `{InstanceId = "i-1234567890abcdef0"}`
    - `alarm_actions` (list(string)) - SNS topic ARNs for notifications
    - `ok_actions` (list(string)) - SNS topic ARNs when alarm recovers
    - `insufficient_data_actions` (list(string)) - Actions for insufficient data
    - `treat_missing_data` (string) - "missing", "ignore", "breaching", "notBreaching"
    - `datapoints_to_alarm` (number) - Datapoints required to trigger alarm
    - `unit` (string) - Metric unit (Seconds, Percent, Count, etc.)
  
  - **Key Inputs (log-group submodule)**:
    - `name` (string) - Log group name
    - `retention_in_days` (number) - Log retention (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)
    - `kms_key_id` (string) - KMS key for encryption
    - `tags` (map(string)) - Tags
  
  - **Key Inputs (metric-alarms-by-multiple-dimensions submodule)**:
    - All fields from `metric-alarm` submodule
    - `dimensions` (map(map(string))) - Map of dimension sets
      - Example: `{"lambda1" = {FunctionName = "index"}, "lambda2" = {FunctionName = "signup"}}`
    - `alarm_name` (string) - Name prefix (actual name will be `"${alarm_name}${key}"`)
  
  - **Key Outputs (metric-alarm submodule)**: 
    - `alarm_arn` (string) - CloudWatch alarm ARN
    - `alarm_id` (string) - Alarm identifier
  
  - **Key Outputs (log-group submodule)**:
    - `log_group_name` (string) - Log group name
    - `log_group_arn` (string) - Log group ARN
  
  - **Secure Defaults**: 
    - KMS encryption support for log groups
    - CIS AWS Foundations benchmark alarms available
    - Data protection policies for PII redaction
    - Log retention configurable (prevents indefinite storage costs)
  
  - **Wiring Considerations**: 
    - **ALB Monitoring Requirements**:
      - **Input from ALB**: `arn_suffix` output → `dimensions.LoadBalancer`
      - **Namespace**: `"AWS/ApplicationELB"`
      - **Recommended Metrics**:
        - `TargetResponseTime` - Average response time (threshold: 1s)
        - `HTTPCode_Target_5XX_Count` - 5xx errors (threshold: 10)
        - `UnHealthyHostCount` - Unhealthy targets (threshold: 0)
        - `HealthyHostCount` - Healthy targets (threshold: < min_size)
        - `RequestCount` - Request volume monitoring
        - `ActiveConnectionCount` - Active connections
      - **Example Dimensions**: `{LoadBalancer = module.alb.arn_suffix}`
    
    - **ASG Monitoring Requirements**:
      - **Input from ASG**: `autoscaling_group_name` output → `dimensions.AutoScalingGroupName`
      - **Namespace**: `"AWS/EC2"`
      - **Recommended Metrics**:
        - `CPUUtilization` - CPU usage (threshold: 80%)
        - `NetworkIn` - Inbound traffic (for capacity planning)
        - `NetworkOut` - Outbound traffic
        - `StatusCheckFailed` - Status check failures (threshold: 0)
        - `StatusCheckFailed_System` - AWS infrastructure issues
        - `StatusCheckFailed_Instance` - Instance OS issues
      - **Example Dimensions**: `{AutoScalingGroupName = module.asg.autoscaling_group_name}`
    
    - **Alarm Actions**:
      - Requires SNS topic ARN: `aws_sns_topic.alerts.arn`
      - Can integrate with PagerDuty, Slack, OpsGenie via SNS subscriptions
    
    - **Type Compatibility**: 
      - ALB `arn_suffix` is string ✅
      - ASG `autoscaling_group_name` is string ✅
      - Dimensions map expects map(string) ✅
      - Alarm actions expect list(string) ✅

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/sns/aws` — SNS topics for alarm notifications
  - `app.terraform.io/hashi-demos-apj/s3-bucket/aws` — S3 buckets for metric stream destinations

- **Glue Resources Needed**: 
  - `aws_sns_topic` - For alarm notifications (can use SNS module or raw resource)
  - `aws_sns_topic_subscription` - Email, SMS, Lambda, or HTTPS endpoints for notifications
  - No glue needed for basic alarm creation

### Rationale

The `cloudwatch` module provides comprehensive monitoring capabilities:

1. **Complete submodule suite** — covers all CloudWatch resource types (alarms, logs, metrics, dashboards)
2. **Modular design** — use only needed submodules (e.g., just `metric-alarm` for ASG+ALB monitoring)
3. **Multi-dimensional support** — batch alarm creation for multiple resources
4. **CIS compliance** — pre-built CIS AWS Foundations benchmark alarms
5. **Flexible alarm configuration** — supports all CloudWatch alarm features
6. **AWS native metrics** — integrates with AWS service namespaces (ALB, EC2, etc.)
7. **Cost optimization** — log retention prevents indefinite storage costs

Module created recently (2025-11-15) and based on HashiCorp's public `terraform-aws-modules/cloudwatch/aws` module (proven pattern).

For ASG+ALB monitoring, the `metric-alarm` submodule is most appropriate:
- **ALB alarms**: Monitor target response time, 5xx errors, healthy/unhealthy host counts
- **ASG alarms**: Monitor CPU utilization, network traffic, status checks
- **Composite alarms**: Combine multiple alarms (e.g., high CPU + high network = scale out)

The `metric-alarms-by-multiple-dimensions` submodule is useful if monitoring multiple ASGs with identical alarm configurations.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/cloudwatch/aws` | Organization policy requires private registry modules |
| Raw `aws_cloudwatch_metric_alarm` | Consumer constitution prohibits raw resources |
| Third-party monitoring (Datadog, New Relic) | AWS-native monitoring preferred, cost considerations |
| CloudWatch dashboards only | Alarms provide proactive alerting, dashboards are reactive |

### Sources

- Private registry: `app.terraform.io/hashi-demos-apj/cloudwatch/aws`
- MCP tool: `get_private_module_details` output for version 5.7.2
- VCS repository: `https://github.com/hashi-demo-lab/terraform-aws-cloudwatch`
- AWS docs: CloudWatch metrics for ALB (`AWS/ApplicationELB` namespace)
- AWS docs: CloudWatch metrics for EC2 (`AWS/EC2` namespace)
- AWS docs: CloudWatch alarm configuration
- CIS AWS Foundations Benchmark v1.4.0
