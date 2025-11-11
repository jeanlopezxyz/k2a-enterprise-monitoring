#!/usr/bin/env bash

# K2A Enterprise Monitoring Kind Setup
# Based on kagent patterns

set -o errexit
set -o pipefail

# Configuration
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-k2a-monitoring}
KIND_IMAGE_VERSION=${KIND_IMAGE_VERSION:-1.31.0}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    command -v kind >/dev/null 2>&1 || error "kind not found"
    command -v kubectl >/dev/null 2>&1 || error "kubectl not found" 
    command -v docker >/dev/null 2>&1 || error "docker not found"
    command -v helm >/dev/null 2>&1 || error "helm not found"
    
    log "Dependencies check passed"
}

# 1. Create registry container unless it already exists
setup_local_registry() {
    log "Setting up local registry..."
    
    local reg_name='k2a-registry'
    local reg_port='5001'
    
    if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
        log "Creating local registry container..."
        docker run \
            -d --restart=always -p "127.0.0.1:${reg_port}:5000" \
            --network bridge --name "${reg_name}" \
            registry:2
    else
        log "Local registry already running"
    fi
}

# 2. Create kind cluster
create_kind_cluster() {
    log "Creating Kind cluster: $KIND_CLUSTER_NAME"
    
    if kind get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
        warn "Kind cluster '${KIND_CLUSTER_NAME}' already exists; skipping create."
        return
    fi
    
    # Create cluster with config
    kind create cluster --name "${KIND_CLUSTER_NAME}" \
        --config "${SCRIPT_DIR}/kind-config.yaml" \
        --image="kindest/node:v${KIND_IMAGE_VERSION}"
    
    log "Kind cluster created successfully"
}

# 3. Configure registry access
configure_registry() {
    log "Configuring registry access..."
    
    local reg_name='k2a-registry' 
    local reg_port='5001'
    
    # Add registry config to nodes
    REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
    for node in $(kind get nodes --name "${KIND_CLUSTER_NAME}"); do
        docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
        cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${reg_name}:5000"]
EOF
    done
    
    # Connect registry to cluster network
    if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
        docker network connect "kind" "${reg_name}"
    fi
    
    # Document local registry
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

    log "Registry configuration completed"
}

# 4. Setup monitoring namespace
setup_monitoring() {
    log "Setting up monitoring prerequisites..."
    
    # Create monitoring namespace
    kubectl create namespace k2a-monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for monitoring
    kubectl label namespace k2a-monitoring \
        name=k2a-monitoring \
        monitoring=enabled \
        --overwrite
    
    log "Monitoring namespace configured"
}

# 5. Verify cluster status
verify_cluster() {
    log "Verifying cluster status..."
    
    # Wait for nodes to be ready
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    # Check cluster info
    kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
    
    # Show node status
    kubectl get nodes -o wide
    
    log "Cluster verification completed"
}

# Main setup function
main() {
    log "Starting K2A Monitoring Kind cluster setup..."
    
    check_dependencies
    setup_local_registry
    create_kind_cluster
    configure_registry
    setup_monitoring
    verify_cluster
    
    log "Kind cluster setup completed successfully!"
    echo ""
    log "Next steps:"
    echo "  1. Build and push images: make docker-build docker-push"
    echo "  2. Deploy K2A Monitoring: make helm-install"
    echo "  3. Access UI: kubectl port-forward -n k2a-monitoring svc/k2a-monitoring-ui 8080:80"
    echo "  4. Test deployment: make test-e2e"
}

# Run main function
main "$@"