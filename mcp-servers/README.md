# K2A MCP Servers

This directory contains MCP (Model Context Protocol) servers for the K2A Enterprise Monitoring system.

## Deployed MCP Servers

| Server | Status | Port | Description |
|--------|--------|------|-------------|
| **prometheus-mcp** | Running | 8000 | Custom K2A MCP for Prometheus metrics and alerts |
| **alertmanager-mcp** | Running | 8000 | Custom K2A MCP for AlertManager operations |
| **redhat-cases-mcp** | Running | 8000 | Custom K2A MCP for Red Hat KB search and case management |
| **kubernetes-mcp** | Running | 8080 | Official Kubernetes MCP from containers/kubernetes-mcp-server |
| **slack-mcp** | Requires Config | 8080 | Official Slack MCP from korotovsky/slack-mcp-server |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    K2A Remediation Agent (kagent)               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     LLM (Claude/GPT)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│              ┌───────────────┼───────────────┐                  │
│              ▼               ▼               ▼                  │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐         │
│  │ prometheus-mcp│ │alertmanager-  │ │kubernetes-mcp │         │
│  │    :8000      │ │  mcp :8000    │ │    :8080      │         │
│  └───────────────┘ └───────────────┘ └───────────────┘         │
│              │               │               │                  │
│              ▼               ▼               ▼                  │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐         │
│  │  Prometheus   │ │ AlertManager  │ │  K8s/OCP API  │         │
│  └───────────────┘ └───────────────┘ └───────────────┘         │
│                                                                 │
│  ┌───────────────┐ ┌───────────────┐                           │
│  │redhat-cases-  │ │  slack-mcp    │                           │
│  │  mcp :8000    │ │    :8080      │                           │
│  └───────────────┘ └───────────────┘                           │
│         │                   │                                   │
│         ▼                   ▼                                   │
│  ┌───────────────┐ ┌───────────────┐                           │
│  │ Red Hat API   │ │  Slack API    │                           │
│  │ (KB + Cases)  │ │               │                           │
│  └───────────────┘ └───────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

## Service URLs (Internal)

```
prometheus-mcp:    http://prometheus-mcp.k2a-mcp-servers.svc.cluster.local:8000/mcp
alertmanager-mcp:  http://alertmanager-mcp.k2a-mcp-servers.svc.cluster.local:8000/mcp
redhat-cases-mcp:  http://redhat-cases-mcp.k2a-mcp-servers.svc.cluster.local:8000/mcp
kubernetes-mcp:    http://kubernetes-mcp.k2a-mcp-servers.svc.cluster.local:8080/mcp
slack-mcp:         http://slack-mcp.k2a-mcp-servers.svc.cluster.local:8080/mcp
```

## Deployment

### Prerequisites
- OpenShift cluster with admin access
- `oc` CLI configured

### Deploy All MCP Servers

```bash
# Login to OpenShift
oc login --server=<API_URL> --username=<USER> --password=<PASS>

# Run deployment script
./scripts/deploy-mcp-servers.sh
```

### Manual Deployment

```bash
# Create namespace
oc create namespace k2a-mcp-servers

# Deploy official MCPs
oc apply -f mcp-servers/kubernetes-mcp/deployment.yaml
oc apply -f mcp-servers/slack-mcp/deployment.yaml

# Build and deploy custom MCPs
oc new-build --binary --strategy=docker --name=prometheus-mcp -n k2a-mcp-servers
oc start-build prometheus-mcp --from-dir=mcp-servers/prometheus-mcp -n k2a-mcp-servers --follow

# Repeat for alertmanager-mcp and redhat-cases-mcp
```

## Configuration

### Slack MCP

Requires Slack OAuth token:

```bash
# Edit the secret with your token
oc edit secret slack-mcp-secrets -n k2a-mcp-servers

# Add your SLACK_MCP_XOXP_TOKEN
```

Get token from: https://api.slack.com/apps (OAuth & Permissions)

### Red Hat Cases MCP

Requires Red Hat API offline token for KB search and case management:

```bash
# Edit the secret
oc edit secret redhat-cases-mcp-secrets -n k2a-mcp-servers

# Add your REDHAT_OFFLINE_TOKEN
```

Get token from: https://access.redhat.com/management/api

### Prometheus MCP

Configure Prometheus URL if different from default:

```bash
oc edit configmap prometheus-mcp-config -n k2a-mcp-servers
# Update PROMETHEUS_URL
```

### AlertManager MCP

Configure AlertManager URL if different from default:

```bash
oc edit configmap alertmanager-mcp-config -n k2a-mcp-servers
# Update ALERTMANAGER_URL
```

## Available Tools

### prometheus-mcp
- `prometheus_query` - Execute instant PromQL query
- `prometheus_query_range` - Execute range query
- `prometheus_alerts` - Get active alerts
- `prometheus_targets` - Get scrape targets
- `prometheus_rules` - Get alerting/recording rules
- `prometheus_health` - Health check

### alertmanager-mcp
- `alertmanager_alerts` - Get active alerts
- `alertmanager_alert_groups` - Get alert groups
- `alertmanager_silences` - List silences
- `alertmanager_create_silence` - Create silence
- `alertmanager_delete_silence` - Delete silence
- `alertmanager_silence_alert` - Silence specific alert
- `alertmanager_receivers` - Get receivers
- `alertmanager_status` - Get status
- `alertmanager_health` - Health check

### redhat-cases-mcp
- `kb_search` - Search Red Hat Knowledge Base
- `kb_get_article` - Get full KB article
- `case_create` - Create support case
- `case_get` - Get case details
- `case_add_comment` - Add comment to case
- `case_list` - List support cases
- `case_escalate` - Request escalation
- `redhat_health` - API connectivity check

### kubernetes-mcp
- `get_pod_logs` - Get pod logs
- `list_pods` - List pods
- `list_namespaces` - List namespaces
- `get_events` - Get cluster events
- `describe_resource` - Describe resource
- `list_resources` - List resources by type
- `exec_command` - Execute command in pod (if enabled)
- `helm_list_releases` - List Helm releases
- `helm_get_values` - Get release values

### slack-mcp
- `channels_list` - List Slack channels
- `conversations_history` - Get channel history
- `conversations_add_message` - Send message (if enabled)

## Troubleshooting

### Check pod status
```bash
oc get pods -n k2a-mcp-servers
```

### View logs
```bash
oc logs deployment/prometheus-mcp -n k2a-mcp-servers
oc logs deployment/alertmanager-mcp -n k2a-mcp-servers
oc logs deployment/redhat-cases-mcp -n k2a-mcp-servers
oc logs deployment/kubernetes-mcp -n k2a-mcp-servers
oc logs deployment/slack-mcp -n k2a-mcp-servers
```

### Rebuild image after code changes
```bash
oc start-build <mcp-name> --from-dir=mcp-servers/<mcp-name> -n k2a-mcp-servers --follow
oc rollout restart deployment/<mcp-name> -n k2a-mcp-servers
```
