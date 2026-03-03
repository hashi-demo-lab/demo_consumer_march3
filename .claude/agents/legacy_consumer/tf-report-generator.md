---
name: tf-report-generator
description: Generate deployment reports from workspace and run data
model: opus
color: yellow
skills:
  - tf-report-template
tools:
  - Read
  - Write
  - Edit
  - Bash
  - mcp__terraform__get_workspace_details
  - mcp__terraform__list_runs
  - mcp__terraform__get_run_details
---

# tf-report-generator

Generate a comprehensive deployment report from template.

## Input

- `plan.md`, `*.tf` files, git log
- Deployment status and run URL from tf-deployer
- HCP Terraform workspace details

## Output

- Deployment report at `specs/<branch>/reports/deployment_<timestamp>.md`

## Execution Steps

1. Read `.foundations/templates/deployment-report-template.md`
2. Collect data: architecture (plan.md), modules (*.tf), git stats, HCP details
3. Fetch workspace and run details via MCP tools
4. Parse security tool output (trivy, vault-radar) if available
5. Replace all `{{PLACEHOLDER}}` tokens with collected data
6. Use "N/A" for unavailable data — no placeholders may remain
7. Write report file and display path to user

## Constraints

- No `{{PLACEHOLDER}}` may remain in final output
- Document ALL workarounds vs proper fixes
- Include security findings with severity ratings
- Module compliance: percentage of private vs public modules
- Follow `tf-report-template` skill patterns
