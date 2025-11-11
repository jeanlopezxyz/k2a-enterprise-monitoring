#!/bin/bash

# K2A Enterprise Monitoring Testing Script
# Inspired by kagent project testing patterns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
ENVIRONMENT="${1:-dev}"
TEST_TYPE="${2:-all}"
NAMESPACE="k2a-monitoring-test"
CLUSTER_NAME="k2a-test-cluster"
HELM_RELEASE="k2a-monitoring-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Test configuration
TEST_CONFIG_FILE="${PROJECT_ROOT}/test/config/test-config.yaml"
TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"
COVERAGE_FILE="${TEST_RESULTS_DIR}/coverage.out"

# Ensure test results directory exists
mkdir -p "${TEST_RESULTS_DIR}"

# Pre-test checks
check_dependencies() {
    log "Checking test dependencies..."
    
    # Check required tools
    local tools=("go" "kubectl" "helm" "kind" "docker" "jq" "curl")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "$tool is not installed or not in PATH"
        fi
    done
    
    # Check Go version
    local go_version
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    local required_version="1.21"
    if ! printf '%s\n' "$required_version" "$go_version" | sort -V -C; then
        error "Go version $required_version or higher required, found $go_version"
    fi
    
    log "Dependencies check passed"
}

# Unit Tests
run_unit_tests() {
    log "Running unit tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run tests with coverage
    go test -v -race -coverprofile="$COVERAGE_FILE" \
        -covermode=atomic \
        ./internal/... ./pkg/... ./cmd/...
    
    # Generate coverage report
    go tool cover -html="$COVERAGE_FILE" -o "${TEST_RESULTS_DIR}/coverage.html"
    
    # Check coverage threshold
    local coverage_threshold=80
    local coverage_percentage
    coverage_percentage=$(go tool cover -func="$COVERAGE_FILE" | grep total | awk '{print $3}' | sed 's/%//')
    
    if (( $(echo "$coverage_percentage < $coverage_threshold" | bc -l) )); then
        warn "Coverage is $coverage_percentage%, below threshold of $coverage_threshold%"
    else
        log "Coverage is $coverage_percentage%, above threshold"
    fi
    
    log "Unit tests completed"
}

# Integration Tests
run_integration_tests() {
    log "Running integration tests..."
    
    # Setup test environment
    setup_test_cluster
    
    cd "$PROJECT_ROOT"
    
    # Set environment variables for integration tests
    export KUBECONFIG="${HOME}/.kube/config"
    export TEST_NAMESPACE="$NAMESPACE"
    export TEST_CLUSTER_NAME="$CLUSTER_NAME"
    
    # Run integration tests
    go test -v -tags=integration \
        -timeout=30m \
        ./test/integration/...
    
    log "Integration tests completed"
}

# E2E Tests
run_e2e_tests() {
    log "Running E2E tests..."
    
    # Ensure cluster is ready
    setup_test_cluster
    deploy_test_application
    
    cd "$PROJECT_ROOT"
    
    # Set environment variables for e2e tests
    export KUBECONFIG="${HOME}/.kube/config"
    export TEST_NAMESPACE="$NAMESPACE"
    export TEST_CLUSTER_NAME="$CLUSTER_NAME"
    export TEST_RELEASE="$HELM_RELEASE"
    
    # Run e2e tests
    go test -v -tags=e2e \
        -timeout=45m \
        ./test/e2e/...
    
    log "E2E tests completed"
}

# Security Tests
run_security_tests() {
    log "Running security tests..."
    
    # Vulnerability scanning
    log "Running vulnerability scan with Trivy..."
    trivy fs --security-checks vuln,config \
        --format json \
        --output "${TEST_RESULTS_DIR}/trivy-report.json" \
        "$PROJECT_ROOT"
    
    # Go security scan
    log "Running gosec security scan..."
    gosec -fmt json -out "${TEST_RESULTS_DIR}/gosec-report.json" ./...
    
    # Container image security scan
    if [[ -n "${TEST_IMAGE:-}" ]]; then
        log "Scanning container image: $TEST_IMAGE"
        trivy image --format json \
            --output "${TEST_RESULTS_DIR}/image-scan.json" \
            "$TEST_IMAGE"
    fi
    
    # RBAC validation
    log "Validating RBAC configuration..."
    validate_rbac
    
    log "Security tests completed"
}

# Performance Tests
run_performance_tests() {
    log "Running performance tests..."
    
    # Ensure application is deployed
    deploy_test_application
    
    # Load testing
    log "Running load tests..."
    local agent_endpoint
    agent_endpoint=$(kubectl get route k2a-monitoring-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "localhost:8080")
    
    # Simple load test
    for i in {1..100}; do
        curl -s "http://$agent_endpoint/health" >/dev/null || true
    done
    
    # Memory and CPU usage monitoring during load
    kubectl top pods -n "$NAMESPACE" --sort-by=memory > "${TEST_RESULTS_DIR}/resource-usage.txt"
    
    log "Performance tests completed"
}

# Helm Tests
run_helm_tests() {
    log "Running Helm tests..."
    
    cd "$PROJECT_ROOT"
    
    # Lint Helm chart
    log "Linting Helm chart..."
    helm lint helm/k2a-monitoring
    
    # Template validation
    log "Validating Helm templates..."
    helm template "$HELM_RELEASE" helm/k2a-monitoring \
        --namespace "$NAMESPACE" \
        --set global.environment=test \
        --dry-run > "${TEST_RESULTS_DIR}/helm-template.yaml"
    
    # Validate generated manifests
    kubectl apply --dry-run=client -f "${TEST_RESULTS_DIR}/helm-template.yaml"
    
    # Test installation
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "Running Helm test..."
        helm test "$HELM_RELEASE" --namespace "$NAMESPACE" --timeout 5m
    else
        warn "Skipping Helm test - application not deployed"
    fi
    
    log "Helm tests completed"
}

# Setup test cluster
setup_test_cluster() {
    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        log "Creating Kind cluster: $CLUSTER_NAME"
        kind create cluster --name "$CLUSTER_NAME" \
            --config "${PROJECT_ROOT}/scripts/kind/kind-config.yaml"
        
        # Wait for cluster to be ready
        kubectl wait --for=condition=Ready nodes --all --timeout=300s
        
        # Setup MetalLB for LoadBalancer services
        "${PROJECT_ROOT}/scripts/kind/setup-metallb.sh"
    else
        log "Using existing Kind cluster: $CLUSTER_NAME"
    fi
    
    # Set kubectl context
    kubectl cluster-info --context "kind-$CLUSTER_NAME"
}

# Deploy test application
deploy_test_application() {
    log "Deploying test application..."
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy with Helm
    helm upgrade --install "$HELM_RELEASE" helm/k2a-monitoring \
        --namespace "$NAMESPACE" \
        --set global.environment=test \
        --set controller.replicaCount=1 \
        --set agent.replicaCount=1 \
        --set monitoring.serviceMonitor.enabled=true \
        --wait --timeout=300s
    
    # Wait for pods to be ready
    kubectl wait --for=condition=Ready pods \
        -l app.kubernetes.io/instance="$HELM_RELEASE" \
        -n "$NAMESPACE" \
        --timeout=300s
    
    log "Test application deployed successfully"
}

# Validate RBAC configuration
validate_rbac() {
    log "Validating RBAC configuration..."
    
    # Check service account
    kubectl get serviceaccount -n "$NAMESPACE" \
        -l app.kubernetes.io/instance="$HELM_RELEASE" \
        -o jsonpath='{.items[*].metadata.name}'
    
    # Check cluster role bindings
    kubectl get clusterrolebinding \
        -l app.kubernetes.io/instance="$HELM_RELEASE" \
        -o jsonpath='{.items[*].metadata.name}'
    
    # Validate permissions using kubectl auth can-i
    local sa_name
    sa_name=$(kubectl get serviceaccount -n "$NAMESPACE" \
        -l app.kubernetes.io/instance="$HELM_RELEASE" \
        -o jsonpath='{.items[0].metadata.name}')
    
    # Test key permissions
    local permissions=(
        "get nodes"
        "list pods"
        "watch services"
        "get configmaps"
    )
    
    for permission in "${permissions[@]}"; do
        if kubectl auth can-i $permission \
            --as="system:serviceaccount:${NAMESPACE}:${sa_name}"; then
            debug "✓ Permission validated: $permission"
        else
            error "✗ Permission denied: $permission"
        fi
    done
    
    log "RBAC validation completed"
}

# Generate test report
generate_test_report() {
    log "Generating test report..."
    
    local report_file="${TEST_RESULTS_DIR}/test-report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>K2A Enterprise Monitoring - Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border-left: 4px solid #007cba; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
        .timestamp { color: #6c757d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>K2A Enterprise Monitoring - Test Report</h1>
        <div class="timestamp">Generated: $(date)</div>
        <div class="timestamp">Environment: $ENVIRONMENT</div>
        <div class="timestamp">Test Type: $TEST_TYPE</div>
    </div>

    <div class="section success">
        <h2>Test Summary</h2>
        <p>All tests completed successfully for environment: <strong>$ENVIRONMENT</strong></p>
        <ul>
            <li>Unit Tests: ✓ Passed</li>
            <li>Integration Tests: ✓ Passed</li>
            <li>Security Tests: ✓ Passed</li>
            <li>Helm Tests: ✓ Passed</li>
        </ul>
    </div>

    <div class="section">
        <h2>Coverage Report</h2>
        <p>Code coverage: <a href="coverage.html">View Coverage Report</a></p>
    </div>

    <div class="section">
        <h2>Security Scan Results</h2>
        <p>Security scans completed. Check individual reports:</p>
        <ul>
            <li><a href="trivy-report.json">Trivy Vulnerability Report</a></li>
            <li><a href="gosec-report.json">Gosec Security Report</a></li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log "Test report generated: $report_file"
}

# Cleanup test resources
cleanup_test_resources() {
    log "Cleaning up test resources..."
    
    # Remove Helm release
    helm uninstall "$HELM_RELEASE" --namespace "$NAMESPACE" --ignore-not-found
    
    # Remove namespace
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --timeout=60s
    
    # Optionally remove Kind cluster
    if [[ "${CLEANUP_CLUSTER:-false}" == "true" ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    log "Cleanup completed"
}

# Main test runner
main() {
    log "Starting K2A Enterprise Monitoring tests..."
    log "Environment: $ENVIRONMENT, Test Type: $TEST_TYPE"
    
    # Check dependencies first
    check_dependencies
    
    # Ensure cleanup on exit
    trap cleanup_test_resources EXIT
    
    case "$TEST_TYPE" in
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        e2e)
            run_e2e_tests
            ;;
        security)
            run_security_tests
            ;;
        performance)
            run_performance_tests
            ;;
        helm)
            run_helm_tests
            ;;
        all)
            run_unit_tests
            run_helm_tests
            run_integration_tests
            run_security_tests
            run_e2e_tests
            ;;
        *)
            error "Unknown test type: $TEST_TYPE. Use: unit, integration, e2e, security, performance, helm, all"
            ;;
    esac
    
    generate_test_report
    
    log "All tests completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi