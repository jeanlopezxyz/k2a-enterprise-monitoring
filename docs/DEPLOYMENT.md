# Guía de Deployment - K2A Enterprise Monitoring

## Prerequisitos

### Software Requerido
- OpenShift CLI (`oc`) v4.10+
- Kustomize v4.5+
- Acceso administrativo al cluster OpenShift

### Permisos Requeridos
- `cluster-admin` para crear SecurityContextConstraints
- Permisos para crear namespaces
- Acceso a `openshift-monitoring` namespace

## Deployment Rápido

### 1. Preparación del Entorno
```bash
# Clonar el repositorio
git clone <repo-url> k2a-enterprise-monitoring
cd k2a-enterprise-monitoring

# Login al cluster OpenShift
oc login <cluster-url> -u <username>

# Verificar acceso
oc whoami
```

### 2. Deployment por Ambiente

#### Desarrollo
```bash
./scripts/deploy.sh dev deploy
```

#### Staging
```bash
./scripts/deploy.sh staging deploy
```

#### Producción
```bash
./scripts/deploy.sh prod deploy
```

### 3. Configurar Monitoring Stack
```bash
# Configurar todo el stack de monitoring
./scripts/monitoring-setup.sh prod all

# O configurar componentes individualmente
./scripts/monitoring-setup.sh prod workload-monitoring
./scripts/monitoring-setup.sh prod metrics
./scripts/monitoring-setup.sh prod grafana
./scripts/monitoring-setup.sh prod alertmanager
```

## Estructura de Deployment

### Componentes Desplegados

1. **RBAC**
   - Namespace: `k2a-monitoring-{env}`
   - ServiceAccount: `k2a-monitoring-sa`
   - ClusterRole/ClusterRoleBinding para acceso a métricas

2. **Seguridad**
   - SecurityContextConstraints personalizado
   - NetworkPolicy para tráfico controlado
   - Pod Security Standards

3. **Aplicación**
   - Deployment del K2A Agent
   - Service para exposición interna
   - Route de OpenShift para acceso externo

4. **Monitoring**
   - ServiceMonitor para Prometheus
   - PrometheusRule para alertas
   - Grafana Dashboard

### Configuración por Ambiente

| Ambiente | Replicas | CPU Request | Memory Request | CPU Limit | Memory Limit |
|----------|----------|-------------|----------------|-----------|--------------|
| dev      | 1        | 100m        | 128Mi          | 500m      | 512Mi        |
| staging  | 2        | 100m        | 128Mi          | 500m      | 512Mi        |
| prod     | 3        | 200m        | 256Mi          | 1000m     | 1Gi          |

## Verificación del Deployment

### 1. Verificar Estado de Pods
```bash
oc get pods -n k2a-monitoring-prod -l app=k2a-monitoring
```

### 2. Verificar Logs
```bash
./scripts/deploy.sh prod logs
```

### 3. Verificar Métricas
```bash
# Port forward al service de métricas
oc port-forward -n k2a-monitoring-prod svc/prod-k2a-monitoring-service 8081:8081

# Acceder a métricas
curl http://localhost:8081/metrics
```

### 4. Verificar Monitoring Stack
```bash
./scripts/monitoring-setup.sh prod verify
```

## Acceso a Componentes

### K2A Monitoring API
```bash
# Obtener URL de la route
oc get route prod-k2a-monitoring-route -n k2a-monitoring-prod -o jsonpath='{.spec.host}'

# Acceso directo con port-forward
oc port-forward -n k2a-monitoring-prod svc/prod-k2a-monitoring-service 8080:8080
curl http://localhost:8080/health
```

### Prometheus
```bash
oc port-forward -n openshift-user-workload-monitoring svc/prometheus-user-workload 9090:9090
# Acceder a http://localhost:9090
```

### Grafana
```bash
oc port-forward -n openshift-monitoring svc/grafana 3000:3000
# Acceder a http://localhost:3000
```

### AlertManager
```bash
oc port-forward -n openshift-user-workload-monitoring svc/alertmanager-user-workload 9093:9093
# Acceder a http://localhost:9093
```

## Troubleshooting

### Problemas Comunes

#### 1. SCC No Aplicado
```bash
# Verificar SCC
oc get scc k2a-monitoring-scc

# Re-aplicar si es necesario
oc apply -f manifests/base/security/scc.yaml
```

#### 2. User Workload Monitoring No Habilitado
```bash
# Verificar configuración
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml

# Habilitar manualmente
./scripts/monitoring-setup.sh prod workload-monitoring
```

#### 3. Pods No Inician
```bash
# Verificar eventos
oc describe pod <pod-name> -n k2a-monitoring-prod

# Verificar logs
oc logs <pod-name> -n k2a-monitoring-prod
```

#### 4. ServiceMonitor No Funciona
```bash
# Verificar que User Workload Monitoring está habilitado
oc get pods -n openshift-user-workload-monitoring

# Verificar configuración del ServiceMonitor
oc describe servicemonitor k2a-monitoring-metrics -n k2a-monitoring-prod
```

## Operaciones de Mantenimiento

### Rollback
```bash
./scripts/deploy.sh prod rollback
```

### Actualización
```bash
# Editar imagen en kustomization.yaml
vim manifests/overlays/prod/kustomization.yaml

# Re-deployar
./scripts/deploy.sh prod deploy
```

### Limpieza
```bash
./scripts/deploy.sh prod cleanup
```

### Escalado Manual
```bash
# Escalar deployment
oc scale deployment prod-k2a-monitoring-agent -n k2a-monitoring-prod --replicas=5

# En producción, usar HPA automático
oc get hpa k2a-monitoring-hpa -n k2a-monitoring-prod
```

## Monitoreo de la Solución

### Métricas Principales
- `k2a_cluster_nodes_total` - Total de nodos
- `k2a_cluster_nodes_ready` - Nodos listos
- `k2a_pods_by_status` - Distribución de pods por estado
- `k2a_node_cpu_usage_percent` - Uso de CPU por nodo
- `k2a_node_memory_usage_percent` - Uso de memoria por nodo

### Alertas Configuradas
- K2AAgentDown - Agente no disponible
- K2AHighMemoryUsage - Alto uso de memoria del agente
- K2AHighCPUUsage - Alto uso de CPU del agente
- ClusterNodeNotReady - Nodo no disponible
- ClusterHighPodRestarts - Alto número de reinicios de pods

## Configuración Avanzada

### Personalizar Configuración
```bash
# Editar configuración del agente
oc edit configmap k2a-agent-config -n k2a-monitoring-prod

# Reiniciar deployment para aplicar cambios
oc rollout restart deployment prod-k2a-monitoring-agent -n k2a-monitoring-prod
```

### Añadir Métricas Custom
```bash
# Editar PrometheusRule
oc edit prometheusrule k2a-monitoring-rules -n k2a-monitoring-prod
```

### Configurar Alerting
```bash
# Editar configuración de AlertManager
oc edit secret alertmanager-user-workload -n openshift-user-workload-monitoring
```