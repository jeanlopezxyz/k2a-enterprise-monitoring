#!/bin/bash
# Deploy MCP Servers to OpenShift
# K2A Enterprise Monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MCP_DIR="$PROJECT_ROOT/mcp-servers"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}K2A MCP Servers Deployment${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift${NC}"
    echo "Please run: oc login --server=<API_URL> --username=<USER> --password=<PASS>"
    exit 1
fi

echo -e "${GREEN}Logged in as: $(oc whoami)${NC}"
echo -e "${GREEN}Cluster: $(oc whoami --show-server)${NC}"

# Create namespace
echo -e "\n${YELLOW}Creating namespace k2a-mcp-servers...${NC}"
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: k2a-mcp-servers
  labels:
    app.kubernetes.io/part-of: k2a-enterprise-monitoring
EOF

# Switch to namespace
oc project k2a-mcp-servers

# Deploy official MCPs first (no build required)
echo -e "\n${YELLOW}Deploying Kubernetes MCP Server...${NC}"
oc apply -f "$MCP_DIR/kubernetes-mcp/deployment.yaml"

echo -e "\n${YELLOW}Deploying Slack MCP Server...${NC}"
oc apply -f "$MCP_DIR/slack-mcp/deployment.yaml"

# Build and deploy custom MCPs
echo -e "\n${YELLOW}Building and deploying custom MCPs...${NC}"

# Function to build and deploy a custom MCP
deploy_custom_mcp() {
    local name=$1
    local dir="$MCP_DIR/$name"

    echo -e "\n${BLUE}Processing $name...${NC}"

    # Apply deployment (includes BuildConfig and ImageStream)
    oc apply -f "$dir/deployment.yaml"

    # Start build
    echo -e "${YELLOW}Starting build for $name...${NC}"
    oc start-build "$name" --from-dir="$dir" --follow || {
        echo -e "${RED}Build failed for $name${NC}"
        return 1
    }

    echo -e "${GREEN}$name deployed successfully${NC}"
}

# Deploy custom MCPs
for mcp in prometheus-mcp alertmanager-mcp redhat-cases-mcp; do
    deploy_custom_mcp "$mcp"
done

# Wait for deployments to be ready
echo -e "\n${YELLOW}Waiting for deployments to be ready...${NC}"

for deployment in kubernetes-mcp slack-mcp prometheus-mcp alertmanager-mcp redhat-cases-mcp; do
    echo -e "Waiting for $deployment..."
    oc rollout status deployment/$deployment --timeout=300s || {
        echo -e "${RED}Deployment $deployment failed to become ready${NC}"
    }
done

# Show status
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Status${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}Pods:${NC}"
oc get pods -n k2a-mcp-servers

echo -e "\n${YELLOW}Services:${NC}"
oc get svc -n k2a-mcp-servers

echo -e "\n${YELLOW}Service Endpoints:${NC}"
for svc in kubernetes-mcp slack-mcp prometheus-mcp alertmanager-mcp redhat-cases-mcp; do
    echo "- $svc: http://$svc.k2a-mcp-servers.svc.cluster.local:8000"
done

echo -e "\n${GREEN}MCP Servers deployment complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Configure secrets for each MCP server (see deployment.yaml files)"
echo "2. Update kagent values.yaml with the correct MCP server URLs"
echo "3. Deploy kagent using Helm"
