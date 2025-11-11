#!/bin/bash

# Script para configurar el stack de monitoring en OpenShift
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuración
ENVIRONMENT="${1:-prod}"
NAMESPACE="k2a-monitoring-${ENVIRONMENT}"

# Colores para output
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

# Configurar User Workload Monitoring
setup_user_workload_monitoring() {
    log "Setting up User Workload Monitoring..."
    
    # Verificar si user workload monitoring está habilitado
    if oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml | grep -q "enableUserWorkload: true"; then
        log "User Workload Monitoring already enabled"
    else
        log "Enabling User Workload Monitoring..."
        
        cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
    prometheusK8s:
      retention: 7d
      volumeClaimTemplate:
        metadata:
          name: prometheusdb
        spec:
          resources:
            requests:
              storage: 20Gi
EOF
        
        # Esperar a que se aplique la configuración
        log "Waiting for User Workload Monitoring to be ready..."
        sleep 30
        
        # Verificar que prometheus-user-workload está ejecutándose
        oc wait --for=condition=available --timeout=300s deployment/prometheus-operator -n openshift-user-workload-monitoring
        log "User Workload Monitoring enabled successfully"
    fi
}

# Configurar Grafana dashboard
setup_grafana_dashboard() {
    log "Setting up Grafana dashboard..."
    
    # Aplicar el ConfigMap del dashboard
    oc apply -f "${PROJECT_ROOT}/manifests/base/monitoring/grafana-dashboard.yaml" -n "$NAMESPACE"
    
    # Crear GrafanaDashboard CR si el operador está disponible
    if oc get crd grafanadashboards.integreatly.org >/dev/null 2>&1; then
        cat <<EOF | oc apply -f -
apiVersion: integreatly.org/v1alpha1
kind: GrafanaDashboard
metadata:
  name: k2a-cluster-overview
  namespace: $NAMESPACE
  labels:
    app: grafana
spec:
  configMapRef:
    name: k2a-grafana-dashboard
    key: k2a-cluster-overview.json
EOF
        log "GrafanaDashboard CR created"
    else
        warn "Grafana operator not found. Dashboard ConfigMap created but not imported."
    fi
}

# Configurar AlertManager
setup_alertmanager() {
    log "Setting up AlertManager configuration..."
    
    # Crear configuración de AlertManager para el namespace
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-user-workload
  namespace: openshift-user-workload-monitoring
type: Opaque
data:
  alertmanager.yaml: $(cat <<YAML | base64 -w 0
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@k2a-monitoring.local'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'k2a-alerts'
  routes:
  - match:
      service: k2a-monitoring
    receiver: 'k2a-monitoring-alerts'

receivers:
- name: 'k2a-alerts'
  email_configs:
  - to: 'admin@k2a-monitoring.local'
    subject: '[K2A] Alert: {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      {{ end }}

- name: 'k2a-monitoring-alerts'
  email_configs:
  - to: 'k2a-team@k2a-monitoring.local'
    subject: '[K2A Monitoring] {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Service: K2A Monitoring
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Severity: {{ .Labels.severity }}
      {{ end }}
YAML
)
EOF
    
    log "AlertManager configuration created"
}

# Configurar métricas custom
setup_custom_metrics() {
    log "Setting up custom metrics collection..."
    
    # Aplicar ServiceMonitor
    oc apply -f "${PROJECT_ROOT}/manifests/base/monitoring/servicemonitor.yaml" -n "$NAMESPACE"
    
    # Aplicar PrometheusRule
    oc apply -f "${PROJECT_ROOT}/manifests/base/monitoring/prometheusrule.yaml" -n "$NAMESPACE"
    
    log "Custom metrics configuration applied"
}

# Verificar monitoring stack
verify_monitoring() {
    log "Verifying monitoring stack..."
    
    # Verificar que Prometheus puede hacer scraping
    local prometheus_pod
    prometheus_pod=$(oc get pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=prometheus --no-headers | head -n1 | awk '{print $1}')
    
    if [[ -n "$prometheus_pod" ]]; then
        log "Prometheus User Workload is running: $prometheus_pod"
        
        # Verificar que puede acceder a nuestro ServiceMonitor
        sleep 10
        local targets_ready
        targets_ready=$(oc exec -n openshift-user-workload-monitoring "$prometheus_pod" -c prometheus -- \
            wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | \
            grep -o "\"health\":\"up\"" | wc -l || echo "0")
        
        log "Active Prometheus targets: $targets_ready"
    else
        error "Prometheus User Workload not found"
    fi
    
    # Verificar ServiceMonitor
    if oc get servicemonitor k2a-monitoring-metrics -n "$NAMESPACE" >/dev/null 2>&1; then
        log "ServiceMonitor is configured"
    else
        error "ServiceMonitor not found"
    fi
    
    # Verificar PrometheusRule
    if oc get prometheusrule k2a-monitoring-rules -n "$NAMESPACE" >/dev/null 2>&1; then
        log "PrometheusRule is configured"
    else
        error "PrometheusRule not found"
    fi
    
    log "Monitoring stack verification completed"
}

# Mostrar información de acceso
show_access_info() {
    log "Monitoring Access Information:"
    echo ""
    
    # Prometheus
    echo "🔍 Prometheus (User Workload):"
    echo "   oc port-forward -n openshift-user-workload-monitoring svc/prometheus-user-workload 9090:9090"
    echo "   Access: http://localhost:9090"
    echo ""
    
    # Grafana
    echo "📊 Grafana:"
    echo "   oc port-forward -n openshift-monitoring svc/grafana 3000:3000"
    echo "   Access: http://localhost:3000"
    echo ""
    
    # AlertManager
    echo "🚨 AlertManager:"
    echo "   oc port-forward -n openshift-user-workload-monitoring svc/alertmanager-user-workload 9093:9093"
    echo "   Access: http://localhost:9093"
    echo ""
    
    # K2A Monitoring API
    if oc get route ${ENVIRONMENT}-k2a-monitoring-route -n "$NAMESPACE" >/dev/null 2>&1; then
        local route_url
        route_url=$(oc get route ${ENVIRONMENT}-k2a-monitoring-route -n "$NAMESPACE" -o jsonpath='{.spec.host}')
        echo "📡 K2A Monitoring API:"
        echo "   https://$route_url"
        echo ""
    fi
    
    # Queries útiles
    echo "📈 Useful Prometheus Queries:"
    echo "   • k2a_cluster_nodes_total - Total cluster nodes"
    echo "   • k2a_pods_by_status - Pod status distribution"
    echo "   • k2a_node_cpu_usage_percent - Node CPU usage"
    echo "   • k2a_node_memory_usage_percent - Node memory usage"
    echo "   • up{job=\"k2a-monitoring\"} - K2A agent health"
}

# Main
main() {
    case "${2:-all}" in
        all)
            setup_user_workload_monitoring
            setup_custom_metrics
            setup_grafana_dashboard
            setup_alertmanager
            verify_monitoring
            show_access_info
            ;;
        workload-monitoring)
            setup_user_workload_monitoring
            ;;
        metrics)
            setup_custom_metrics
            ;;
        grafana)
            setup_grafana_dashboard
            ;;
        alertmanager)
            setup_alertmanager
            ;;
        verify)
            verify_monitoring
            ;;
        info)
            show_access_info
            ;;
        *)
            echo "Usage: $0 <environment> [all|workload-monitoring|metrics|grafana|alertmanager|verify|info]"
            echo "Environments: dev, staging, prod"
            exit 1
            ;;
    esac
}

main "$@"