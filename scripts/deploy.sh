#!/bin/bash

# Script de deployment para K2A Enterprise Monitoring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuración
ENVIRONMENT="${1:-dev}"
NAMESPACE="k2a-monitoring-${ENVIRONMENT}"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests/overlays/${ENVIRONMENT}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Validaciones
validate_environment() {
    case $ENVIRONMENT in
        dev|staging|prod)
            log "Deploying to environment: $ENVIRONMENT"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Use: dev, staging, or prod"
            ;;
    esac
}

# Verificar dependencias
check_dependencies() {
    log "Checking dependencies..."
    
    command -v oc >/dev/null 2>&1 || error "oc CLI not found"
    command -v kustomize >/dev/null 2>&1 || error "kustomize not found"
    
    # Verificar conexión al cluster
    oc whoami >/dev/null 2>&1 || error "Not logged in to OpenShift cluster"
    
    log "Dependencies check passed"
}

# Crear el SCC antes del deployment
create_scc() {
    log "Creating SecurityContextConstraints..."
    
    # Verificar si el SCC ya existe
    if oc get scc k2a-monitoring-scc >/dev/null 2>&1; then
        warn "SCC k2a-monitoring-scc already exists, updating..."
        kustomize build "${MANIFESTS_DIR}" | oc apply -f - --dry-run=client
    else
        log "Creating new SCC..."
        oc create -f "${PROJECT_ROOT}/manifests/base/security/scc.yaml"
    fi
}

# Deployment principal
deploy() {
    log "Starting deployment to $ENVIRONMENT environment..."
    
    # Verificar que el directorio de manifiestos existe
    [[ -d "$MANIFESTS_DIR" ]] || error "Manifests directory not found: $MANIFESTS_DIR"
    
    # Crear namespace si no existe
    if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "Creating namespace: $NAMESPACE"
        oc create namespace "$NAMESPACE"
    fi
    
    # Aplicar manifiestos
    log "Applying manifests..."
    kustomize build "$MANIFESTS_DIR" | oc apply -f -
    
    # Esperar a que el deployment esté ready
    log "Waiting for deployment to be ready..."
    oc rollout status deployment/${ENVIRONMENT}-k2a-monitoring-agent -n "$NAMESPACE" --timeout=300s
    
    # Verificar el estado
    verify_deployment
}

# Verificar deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Verificar pods
    local pods_ready
    pods_ready=$(oc get pods -n "$NAMESPACE" -l app=k2a-monitoring --no-headers | awk '{print $2}' | grep -c "1/1" || true)
    local total_pods
    total_pods=$(oc get pods -n "$NAMESPACE" -l app=k2a-monitoring --no-headers | wc -l)
    
    if [[ "$pods_ready" -eq "$total_pods" ]] && [[ "$total_pods" -gt 0 ]]; then
        log "All pods are ready ($pods_ready/$total_pods)"
    else
        error "Not all pods are ready ($pods_ready/$total_pods)"
    fi
    
    # Verificar service
    if oc get service ${ENVIRONMENT}-k2a-monitoring-service -n "$NAMESPACE" >/dev/null 2>&1; then
        log "Service is available"
    else
        error "Service not found"
    fi
    
    # Mostrar información de la route
    if [[ "$ENVIRONMENT" != "dev" ]]; then
        local route_url
        route_url=$(oc get route ${ENVIRONMENT}-k2a-monitoring-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")
        log "Route URL: https://$route_url"
    fi
    
    log "Deployment verification completed successfully!"
}

# Función de rollback
rollback() {
    log "Rolling back deployment..."
    oc rollout undo deployment/${ENVIRONMENT}-k2a-monitoring-agent -n "$NAMESPACE"
    oc rollout status deployment/${ENVIRONMENT}-k2a-monitoring-agent -n "$NAMESPACE"
    log "Rollback completed"
}

# Función de cleanup
cleanup() {
    warn "Cleaning up K2A monitoring resources..."
    oc delete namespace "$NAMESPACE" --ignore-not-found=true
    oc delete scc k2a-monitoring-scc --ignore-not-found=true
    log "Cleanup completed"
}

# Función de logs
logs() {
    log "Showing logs for K2A monitoring pods..."
    oc logs -l app=k2a-monitoring -n "$NAMESPACE" --tail=50 -f
}

# Main
main() {
    case "${2:-deploy}" in
        deploy)
            validate_environment
            check_dependencies
            create_scc
            deploy
            ;;
        rollback)
            validate_environment
            rollback
            ;;
        cleanup)
            validate_environment
            cleanup
            ;;
        logs)
            validate_environment
            logs
            ;;
        verify)
            validate_environment
            verify_deployment
            ;;
        *)
            echo "Usage: $0 <environment> [deploy|rollback|cleanup|logs|verify]"
            echo "Environments: dev, staging, prod"
            exit 1
            ;;
    esac
}

main "$@"