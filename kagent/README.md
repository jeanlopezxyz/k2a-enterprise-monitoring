# K2A Enterprise Monitoring - Kagent AI Agent

Este directorio contiene la configuración para desplegar **Kagent** como agente de IA para auto-remediación inteligente del cluster.

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    K2A Intelligent Remediation Agent                        │
│                         (Powered by Kagent)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │  Prometheus  │    │ AlertManager │    │   Red Hat    │                  │
│  │     MCP      │    │     MCP      │    │  Cases MCP   │                  │
│  │  (Tu repo)   │    │  (Tu repo)   │    │  (Tu repo)   │                  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘                  │
│         │                   │                   │                          │
│         ▼                   ▼                   ▼                          │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │              K2A Remediation Agent (Kagent)                 │           │
│  │                                                             │           │
│  │  1. MONITOR  → Revisa métricas con Prometheus MCP           │           │
│  │  2. DETECT   → Recibe alertas de AlertManager MCP           │           │
│  │  3. SEARCH   → Busca soluciones en Red Hat KB MCP           │           │
│  │  4. ANALYZE  → LLM analiza y crea plan de remediación       │           │
│  │  5. NOTIFY   → Envía plan a Slack para aprobación           │           │
│  │  6. EXECUTE  → Ejecuta remediación via Kubernetes MCP       │           │
│  │  7. VERIFY   → Verifica que el problema está resuelto       │           │
│  │  8. ESCALATE → Si falla, crea caso en Red Hat               │           │
│  │                                                             │           │
│  └─────────────────────────────────────────────────────────────┘           │
│         │                   │                   │                          │
│         ▼                   ▼                   ▼                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │   Slack MCP  │    │  Kubernetes  │    │     LLM      │                  │
│  │  (Oficial)   │    │  MCP (Oficial)│   │ (Anthropic)  │                  │
│  └──────────────┘    └──────────────┘    └──────────────┘                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Estructura de Directorios

```
kagent/
├── base/
│   ├── kustomization.yaml    # Kustomization base
│   ├── values.yaml           # Valores del Helm chart de Kagent
│   ├── namespace.yaml        # Namespace k2a-monitoring
│   └── secrets.yaml          # Template de secrets (NO COMMITEAR VALORES)
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        ├── pdb.yaml          # PodDisruptionBudget
        └── hpa.yaml          # HorizontalPodAutoscaler
```

## Componentes

### MCPs Incluidos

| MCP | Fuente | Descripción |
|-----|--------|-------------|
| **prometheus-mcp** | Tu repo GitHub | Queries PromQL, obtener alertas |
| **alertmanager-mcp** | Tu repo GitHub | Gestionar alertas, silences |
| **redhat-cases-mcp** | Tu repo GitHub | Buscar KB, crear casos |
| **slack-mcp** | [korotovsky/slack-mcp-server](https://github.com/korotovsky/slack-mcp-server) | Notificaciones, aprobaciones |
| **kubernetes-mcp** | [feiskyer/mcp-kubernetes-server](https://github.com/feiskyer/mcp-kubernetes-server) | Operaciones kubectl |

### Agentes Kagent Habilitados

- **k8s-agent**: Operaciones de Kubernetes
- **promql-agent**: Queries de Prometheus
- **observability-agent**: Monitoreo general
- **helm-agent**: Operaciones de Helm
- **k2a-remediation-agent**: **Agente personalizado de auto-remediación**

## Requisitos Previos

1. **Kagent instalado en el cluster**
   ```bash
   # Instalar CRDs de Kagent
   helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
     --namespace kagent --create-namespace
   ```

2. **Secrets configurados**
   ```bash
   # Crear secrets (reemplaza con valores reales)
   kubectl create secret generic k2a-llm-secrets \
     --namespace k2a-monitoring \
     --from-literal=ANTHROPIC_API_KEY=sk-ant-xxx

   kubectl create secret generic k2a-slack-secrets \
     --namespace k2a-monitoring \
     --from-literal=SLACK_MCP_XOXP_TOKEN=xoxp-xxx

   kubectl create secret generic k2a-redhat-secrets \
     --namespace k2a-monitoring \
     --from-literal=REDHAT_API_TOKEN=xxx \
     --from-literal=REDHAT_OFFLINE_TOKEN=xxx
   ```

3. **Tus MCPs personalizados**
   - Actualiza las imágenes en `base/values.yaml`:
     - `ghcr.io/YOUR_ORG/prometheus-mcp:latest`
     - `ghcr.io/YOUR_ORG/alertmanager-mcp:latest`
     - `ghcr.io/YOUR_ORG/redhat-cases-mcp:latest`

## Despliegue

### Con Kustomize

```bash
# Development
kubectl apply -k kagent/overlays/dev

# Staging
kubectl apply -k kagent/overlays/staging

# Production
kubectl apply -k kagent/overlays/prod
```

### Con ArgoCD

Los ApplicationSets en `gitops/argocd/applicationset.yaml` despliegan automáticamente:

```bash
# Aplicar ApplicationSets
kubectl apply -f gitops/argocd/project.yaml
kubectl apply -f gitops/argocd/applicationset.yaml

# Verificar applications
kubectl get applications -n openshift-gitops | grep k2a-kagent
```

## Configuración por Ambiente

| Configuración | Dev | Staging | Prod |
|---------------|-----|---------|------|
| Réplicas Controller | 1 | 2 | 3 |
| Log Level | debug | info | info |
| Auto-Remediate | No | Sí | Sí |
| Require Approval | Sí | Sí | Solo high-risk |
| HPA | No | No | Sí (3-10) |
| PDB | No | No | Sí (min 2) |

## Flujo de Auto-Remediación

```
┌─────────────────┐
│   Alerta Firing │
│   (Prometheus)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Recolectar      │
│ Contexto        │
│ - Métricas      │
│ - Logs          │
│ - Events        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Buscar en       │
│ Red Hat KB      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ LLM Analiza     │
│ y Crea Plan     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ ¿Requiere       │ Sí  │ Notificar Slack │
│ Aprobación?     ├────►│ y Esperar       │
└────────┬────────┘     └────────┬────────┘
         │ No                    │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│ Ejecutar        │◄────┤ Aprobado?       │
│ Remediación     │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Verificar       │
│ Resolución      │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌───────────┐
│ OK    │ │ Fallido   │
│ ✓     │ │ (retry)   │
└───────┘ └─────┬─────┘
                │
                ▼ (después de 3 intentos)
         ┌───────────┐
         │ Crear     │
         │ Caso RH   │
         └───────────┘
```

## Acciones de Remediación Soportadas

### Sin Aprobación (Auto)
- Reiniciar pods en namespaces no críticos
- Escalar UP deployments
- Crear silences en AlertManager
- Queries de diagnóstico

### Con Aprobación (Slack)
- Escalar DOWN deployments
- Reiniciar pods en `kube-system`, `openshift-*`
- Aplicar patches de configuración
- Crear casos en Red Hat

## Monitoreo del Agente

```bash
# Ver logs del agente
kubectl logs -f -l app.kubernetes.io/name=kagent -n k2a-monitoring

# Ver estado de los agentes
kubectl get agents -n k2a-monitoring

# Ver estado de los ToolServers
kubectl get toolservers -n k2a-monitoring

# Acceder al UI de Kagent
kubectl port-forward svc/k2a-kagent-ui 8080:80 -n k2a-monitoring
```

## Troubleshooting

### El agente no se conecta a los MCPs

```bash
# Verificar que los ToolServers están running
kubectl get toolservers -n k2a-monitoring -o wide

# Ver logs de un ToolServer específico
kubectl logs -l toolserver=prometheus-mcp -n k2a-monitoring
```

### Errores de autenticación con LLM

```bash
# Verificar secrets
kubectl get secret k2a-llm-secrets -n k2a-monitoring -o yaml

# Verificar que el ModelConfig apunta al secret correcto
kubectl get modelconfig -n k2a-monitoring -o yaml
```

### Slack no recibe notificaciones

```bash
# Verificar token de Slack
kubectl get secret k2a-slack-secrets -n k2a-monitoring

# Probar conectividad del MCP
kubectl logs -l toolserver=slack-mcp -n k2a-monitoring
```

## Referencias

- [Kagent Documentation](https://kagent.dev/docs)
- [Kagent GitHub](https://github.com/kagent-dev/kagent)
- [MCP Specification](https://modelcontextprotocol.io)
- [Slack MCP Server](https://github.com/korotovsky/slack-mcp-server)
- [Kubernetes MCP Server](https://github.com/feiskyer/mcp-kubernetes-server)
