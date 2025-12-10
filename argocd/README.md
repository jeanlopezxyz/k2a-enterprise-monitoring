# ArgoCD Configuration - K2A Enterprise Monitoring

Este directorio contiene la configuracion de ArgoCD para desplegar el stack completo de K2A Enterprise Monitoring.

## Estructura

```
argocd/
├── README.md                        # Este archivo
├── project.yaml                     # AppProject (configuracion base)
│
├── apps/                            # Aplicaciones ArgoCD
│   ├── 00-app-of-apps.yaml          # Orquestador (despliega todo)
│   ├── 01-kmcp-operator.yaml        # Wave -1: Operador kmcp
│   ├── 02-kagent-operator.yaml      # Wave  0: Operador kagent
│   └── 03-k2a-app.yaml              # Wave  1: Aplicacion K2A
│
└── values/                          # Valores (mismo nombre que la app)
    ├── 01-kmcp-operator.yaml        # → apps/01-kmcp-operator.yaml
    ├── 02-kagent-operator.yaml      # → apps/02-kagent-operator.yaml
    └── 03-k2a-app.yaml              # → apps/03-k2a-app.yaml
```

## Orden de Despliegue

Las aplicaciones usan **sync-waves** para desplegarse en el orden correcto:

| Archivo | Wave | Namespace | Descripcion |
|---------|------|-----------|-------------|
| `apps/01-kmcp-operator.yaml` | -1 | kmcp-system | Operador kmcp (CRDs + Controller) |
| `apps/02-kagent-operator.yaml` | 0 | kagent | Operador kagent |
| `apps/03-k2a-app.yaml` | 1 | k2a-mcp-servers, kagent | Aplicacion K2A completa |

## Despliegue Rapido

### Prerequisitos

```bash
# Crear namespace y secret de OpenAI
kubectl create namespace kagent
kubectl create secret generic kagent-openai-secret \
  --namespace kagent \
  --from-literal=api-key="${OPENAI_API_KEY}"
```

### Opcion 1: Desplegar Todo (Recomendado)

```bash
# Aplicar el App-of-Apps (despliega todo automaticamente)
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/apps/00-app-of-apps.yaml
```

### Opcion 2: Desplegar Individualmente

```bash
# Aplicar en orden (los numeros indican el orden)
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/apps/01-kmcp-operator.yaml
kubectl apply -f argocd/apps/02-kagent-operator.yaml
kubectl apply -f argocd/apps/03-k2a-app.yaml
```

## Verificar Despliegue

```bash
# Ver estado de las aplicaciones
argocd app list

# Ver pods en cada namespace
kubectl get pods -n kmcp-system
kubectl get pods -n kagent
kubectl get pods -n k2a-mcp-servers

# Ver recursos de kagent
kubectl get agents,modelconfigs,remotemcpservers -n kagent

# Ver MCPServers de kmcp
kubectl get mcpservers -A
```

## Gestion de Secrets

El secret del modelo LLM debe crearse **ANTES** de desplegar el chart `k2a-agent`:

```bash
# Crear namespace si no existe
kubectl create namespace kagent

# Crear secret de OpenAI
kubectl create secret generic kagent-openai-secret \
  --namespace kagent \
  --from-literal=api-key="sk-..."
```

El `ModelConfig` se crea automaticamente por el Helm chart de `k2a-agent`.
La configuracion del modelo esta en `values/k2a-agent-prod.yaml`:

```yaml
modelConfig:
  create: true
  name: k2a-model-config
  provider: openai
  model: gpt-4o
  secretRef:
    name: kagent-openai-secret  # Referencia al secret
    key: api-key
```

## Personalizacion

### Modificar Valores de Produccion

Edita los archivos en `argocd/values/`:

- `01-kmcp-operator.yaml` - Configuracion del operador kmcp
- `02-kagent-operator.yaml` - Configuracion del operador kagent
- `03-k2a-app.yaml` - Configuracion de MCP Servers + K2A Agent

### Deshabilitar Componentes

Para deshabilitar un MCP server, edita `03-k2a-app.yaml`:

```yaml
servers:
  prometheus:
    enabled: true   # Habilitado
  alertmanager:
    enabled: true   # Habilitado
  redhatCases:
    enabled: false  # Deshabilitado
```

## Troubleshooting

### Ver logs de ArgoCD

```bash
# Logs del application controller
kubectl logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller -f

# Logs de una aplicacion especifica
argocd app logs k2a-stack
```

### Sincronizar manualmente

```bash
# Sincronizar todo el stack
argocd app sync k2a-stack

# Sincronizar una aplicacion especifica
argocd app sync kagent
```

### Rollback

```bash
# Ver historial
argocd app history k2a-agent

# Rollback a revision anterior
argocd app rollback k2a-agent <revision>
```
