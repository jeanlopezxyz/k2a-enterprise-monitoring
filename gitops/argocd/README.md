# K2A Enterprise Monitoring - GitOps con ArgoCD

Este directorio contiene la configuración de GitOps para desplegar K2A Enterprise Monitoring usando ArgoCD con ApplicationSets.

## Estructura

```
gitops/argocd/
├── project.yaml           # AppProject con roles y políticas
├── applicationset.yaml    # ApplicationSet para multi-ambiente
└── README.md             # Esta documentación
```

## Componentes

### AppProject (`project.yaml`)

Define el proyecto ArgoCD con:

- **Source Repos**: Repositorios permitidos
- **Destinations**: Clusters y namespaces autorizados
- **Resource Whitelist**: Recursos permitidos (cluster y namespace scope)
- **Roles**: Admin, Developer, Viewer con políticas RBAC
- **Sync Windows**: Ventanas de despliegue por ambiente

### ApplicationSet (`applicationset.yaml`)

Contiene tres variantes de ApplicationSet:

1. **List Generator** (principal): Configuración explícita por ambiente
2. **Matrix Generator**: Para escenarios multi-cluster
3. **Git Generator**: Auto-discovery de ambientes desde directorios Git

## Ambientes

| Ambiente | Namespace | Branch | Auto-Sync | Réplicas |
|----------|-----------|--------|-----------|----------|
| dev | k2a-monitoring-dev | develop | Si | 1 |
| staging | k2a-monitoring-staging | release/* | Si | 2 |
| prod | k2a-monitoring-prod | main | No | 3 |

## Requisitos Previos

```bash
# OpenShift GitOps Operator instalado
oc get csv -n openshift-gitops | grep gitops

# Verificar ArgoCD está corriendo
oc get pods -n openshift-gitops
```

## Instalación

### 1. Aplicar el AppProject

```bash
oc apply -f gitops/argocd/project.yaml
```

### 2. Aplicar el ApplicationSet

```bash
# Usar el ApplicationSet principal (List Generator)
oc apply -f gitops/argocd/applicationset.yaml
```

### 3. Verificar las Applications creadas

```bash
# Listar applications
oc get applications -n openshift-gitops

# Ver estado detallado
oc get applications -n openshift-gitops -o wide
```

## Sync Windows

Las ventanas de sincronización están configuradas así:

| Ambiente | Horario | Descripción |
|----------|---------|-------------|
| dev | 24/7 | Siempre permitido |
| staging | Lun-Vie 8am-6pm ET | Solo horario laboral |
| prod | Mar/Jue 2-4am ET | Solo ventanas de mantenimiento |

## Roles y Permisos

### Admin
- Acceso completo a todas las applications
- Puede sync, delete, exec en pods
- Grupos: `k2a-admins`, `platform-team`

### Developer
- Puede ver todas las applications
- Puede sync solo dev y staging
- Grupos: `k2a-developers`

### Viewer
- Solo lectura en todas las applications
- Grupos: `k2a-viewers`

## Comandos Útiles

```bash
# Ver estado de sync
argocd app list --project k2a-monitoring

# Sync manual de producción
argocd app sync k2a-monitoring-prod

# Ver diferencias antes de sync
argocd app diff k2a-monitoring-prod

# Rollback a versión anterior
argocd app rollback k2a-monitoring-prod 1

# Ver historial de deployments
argocd app history k2a-monitoring-prod

# Refresh desde Git
argocd app get k2a-monitoring-dev --refresh
```

## Notificaciones

Las applications están configuradas para enviar notificaciones a Slack:

- `#k2a-deployments`: Syncs exitosos
- `#k2a-alerts`: Syncs fallidos y degraded health

Configurar el secret de Slack en ArgoCD:
```bash
oc -n openshift-gitops create secret generic argocd-notifications-secret \
  --from-literal=slack-token=xoxb-your-token
```

## Troubleshooting

### Application no sincroniza

```bash
# Ver eventos de la application
argocd app get k2a-monitoring-dev

# Ver logs del controller
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller
```

### Sync window bloqueando deploy

```bash
# Ver sync windows activas
argocd proj windows list k2a-monitoring

# Override manual (requiere admin)
argocd app sync k2a-monitoring-prod --force
```

### Recursos huérfanos

```bash
# Listar recursos huérfanos
argocd app resources k2a-monitoring-prod --orphaned

# Eliminar recursos huérfanos
argocd app sync k2a-monitoring-prod --prune
```

## Personalización

### Agregar nuevo ambiente

1. Crear overlay en `manifests/overlays/<nuevo-env>/`
2. Agregar elemento al list generator en `applicationset.yaml`
3. Agregar destination al `project.yaml`

### Multi-cluster

Descomentar la sección de clusters en el Matrix Generator y configurar:

```yaml
- cluster: cluster-west
  clusterUrl: https://cluster-west.example.com:6443
  region: us-west
```

### Helm en lugar de Kustomize

Modificar el source en el template:

```yaml
source:
  repoURL: 'https://github.com/your-org/k2a-enterprise-monitoring.git'
  targetRevision: '{{ .revision }}'
  path: 'helm/k2a-monitoring'
  helm:
    valueFiles:
      - 'values-{{ .env }}.yaml'
```
