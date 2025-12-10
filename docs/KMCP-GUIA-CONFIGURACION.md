# kMCP - Guia Completa de Configuracion

## Tabla de Contenidos

1. [Metodos de Instalacion](#metodos-de-instalacion)
   - [Quick Start con CLI](#quick-start-con-cli)
   - [Instalacion con Helm](#instalacion-con-helm)
   - [Instalacion con ArgoCD](#instalacion-con-argocd)
2. [Introduccion](#introduccion)
3. [Arquitectura de kMCP](#arquitectura-de-kmcp)
4. [Recursos de Kubernetes Creados Durante la Instalacion](#recursos-de-kubernetes-creados-durante-la-instalacion)
5. [CRD MCPServer - Especificacion Completa](#crd-mcpserver---especificacion-completa)
6. [Tipos de Transporte](#tipos-de-transporte)
7. [Configuracion del Helm Chart](#configuracion-del-helm-chart)
8. [Ejemplos Practicos](#ejemplos-practicos)
9. [Integracion con kagent](#integracion-con-kagent)
10. [Troubleshooting](#troubleshooting)

---

## Metodos de Instalacion

kMCP ofrece multiples formas de instalacion segun tus necesidades:

| Metodo | Caso de Uso | Descripcion |
|--------|-------------|-------------|
| **CLI (kmcp)** | Desarrollo rapido | Scaffolding, build, deploy en un solo comando |
| **Helm** | Produccion | Solo el controller, MCPServers via manifiestos |
| **ArgoCD** | GitOps, produccion enterprise | Despliegue declarativo del controller |

### Prerequisitos

Antes de comenzar, asegurate de tener instalados:

- **Docker** - Para construir imagenes de MCP servers
- **kubectl** - Para interactuar con tu cluster
- **Helm** - Para instalacion via Helm/ArgoCD
- **kind** (opcional) - Para crear un cluster local de pruebas
- **uv** (opcional) - Para ejecutar FastMCP servers localmente
- **MCP Inspector** (opcional) - Para probar MCP servers

```bash
# Instalar MCP Inspector
npm install -g @modelcontextprotocol/inspector
```

---

### Quick Start con CLI

La forma mas rapida de desarrollar y desplegar MCP servers es usando el CLI oficial.

#### 1. Instalar el CLI

```bash
curl -fsSL https://raw.githubusercontent.com/kagent-dev/kmcp/refs/heads/main/scripts/get-kmcp.sh | bash
```

Verificar instalacion:
```bash
kmcp --help
```

#### 2. Crear un MCP Server (Scaffold)

```bash
# Crear proyecto FastMCP Python
kmcp init python my-mcp-server

# Alternativa: Crear proyecto MCP Go
kmcp init go my-mcp-server
```

Esto crea la siguiente estructura:
```
my-mcp-server/
├── src/
│   └── main.py          # Codigo del MCP server
├── kmcp.yaml            # Configuracion de kmcp
├── pyproject.toml       # Dependencias Python
└── Dockerfile           # Para construir la imagen
```

#### 3. Probar Localmente

```bash
kmcp run --project-dir my-mcp-server
```

Esto:
- Construye la imagen Docker
- Abre el MCP Inspector automaticamente
- Conecta al MCP server via stdio

**Configuracion del MCP Inspector:**
- Transport Type: `STDIO`
- Command: `uv`
- Arguments: `run python src/main.py`

#### 4. Instalar el Controller en Kubernetes

```bash
# Crear cluster kind (opcional)
kind create cluster

# Instalar CRDs
helm install kmcp-crds oci://ghcr.io/kagent-dev/kmcp/helm/kmcp-crds \
  --namespace kmcp-system \
  --create-namespace

# Instalar controller
kmcp install
```

Verificar instalacion:
```bash
kubectl get pods -n kmcp-system
# NAME                                       READY   STATUS    RESTARTS   AGE
# kmcp-controller-manager-66c8764c66-8h5sl   1/1     Running   0          1m
```

#### 5. Build y Deploy del MCP Server

```bash
# Construir imagen y cargar a kind
kmcp build --project-dir my-mcp-server -t my-mcp-server:latest --kind-load-cluster kind

# Desplegar el MCP server
kmcp deploy --file my-mcp-server/kmcp.yaml --image my-mcp-server:latest
```

**Configuracion del MCP Inspector (despues del deploy):**
- Transport Type: `Streamable HTTP`
- URL: `http://127.0.0.1:3000/mcp`

#### Comandos CLI Disponibles

| Comando | Descripcion |
|---------|-------------|
| `kmcp init <framework> <dir>` | Crear scaffold (python, go) |
| `kmcp run --project-dir <dir>` | Ejecutar localmente |
| `kmcp build --project-dir <dir> -t <tag>` | Construir imagen Docker |
| `kmcp install` | Instalar controller en cluster |
| `kmcp deploy --file <kmcp.yaml> --image <tag>` | Desplegar MCP server |
| `kmcp uninstall` | Desinstalar controller |

---

### Instalacion con Helm

Para entornos de produccion o cuando necesitas mayor control.

#### 1. Agregar el Repositorio

```bash
helm repo add kmcp https://kagent-dev.github.io/kmcp
helm repo update
```

#### 2. Instalar CRDs (Separado)

```bash
helm install kmcp-crds kmcp/kmcp-crds \
  --namespace kmcp-system \
  --create-namespace
```

O directamente desde OCI:
```bash
helm install kmcp-crds oci://ghcr.io/kagent-dev/kmcp/helm/kmcp-crds \
  --namespace kmcp-system \
  --create-namespace
```

#### 3. Instalar el Controller

```bash
# Instalacion basica
helm install kmcp kmcp/kmcp \
  --namespace kmcp-system

# Instalacion con valores personalizados
helm install kmcp kmcp/kmcp \
  --namespace kmcp-system \
  -f values.yaml
```

#### Ejemplo de values.yaml

```yaml
# Override del nombre
nameOverride: ""
fullnameOverride: ""
namespaceOverride: ""

# Imagen del controller
image:
  repository: ghcr.io/kagent-dev/kmcp/controller
  pullPolicy: IfNotPresent
  # tag: "" # Por defecto usa appVersion

# Configuracion del Controller
controller:
  replicaCount: 1

  # Leader Election para HA
  leaderElection:
    enabled: true

  # Health Probes
  healthProbe:
    bindAddress: ":8081"
    livenessProbe:
      initialDelaySeconds: 15
      periodSeconds: 20
    readinessProbe:
      initialDelaySeconds: 5
      periodSeconds: 10

  # Metricas Prometheus
  metrics:
    enabled: true
    bindAddress: ":8443"
    secureServing: true

# Security Context
podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - "ALL"

# Recursos
resources:
  limits:
    cpu: 500m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 64Mi

# Service Account
serviceAccount:
  create: true
  annotations: {}
  name: ""

# RBAC
rbac:
  create: true
```

---

### Instalacion con ArgoCD

Para entornos GitOps y produccion enterprise.

#### Opcion 1: Application Simple

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kmcp
  namespace: argocd
spec:
  project: default
  sources:
    # CRDs (se instalan primero)
    - repoURL: https://kagent-dev.github.io/kmcp
      chart: kmcp-crds
      targetRevision: 0.1.0
    # Controller
    - repoURL: https://kagent-dev.github.io/kmcp
      chart: kmcp
      targetRevision: 0.1.0
      helm:
        values: |
          controller:
            replicaCount: 1
            leaderElection:
              enabled: true
          resources:
            limits:
              cpu: 500m
              memory: 128Mi
            requests:
              cpu: 10m
              memory: 64Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: kmcp-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

#### Opcion 2: Separar CRDs y Controller

**CRDs Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kmcp-crds
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  source:
    repoURL: https://kagent-dev.github.io/kmcp
    chart: kmcp-crds
    targetRevision: 0.1.0
  destination:
    server: https://kubernetes.default.svc
    namespace: kmcp-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - Replace=true
```

**Controller Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kmcp-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://kagent-dev.github.io/kmcp
    chart: kmcp
    targetRevision: 0.1.0
    helm:
      valueFiles:
        - values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: kmcp-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Opcion 3: Desde Repositorio Git

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kmcp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/tu-org/tu-repo.git
    path: helm/kmcp
    targetRevision: main
    helm:
      valueFiles:
        - values/base.yaml
        - values/prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: kmcp-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

### Comparacion de Metodos de Instalacion

| Caracteristica | CLI | Helm | ArgoCD |
|----------------|-----|------|--------|
| **Scaffolding** | Si | No | No |
| **Build local** | Si | No | No |
| **Deploy MCP servers** | Si (kmcp deploy) | Via kubectl | Via GitOps |
| **Produccion** | No recomendado | Si | Si |
| **GitOps** | No | Manual | Si |
| **Recomendado para** | Desarrollo | Produccion simple | Produccion enterprise |

---

### Verificar la Instalacion

```bash
# Ver pods del controller
kubectl get pods -n kmcp-system

# Ver CRDs instalados
kubectl get crd | grep kagent

# Ver MCPServers desplegados
kubectl get mcpservers -A

# Ver logs del controller
kubectl logs -n kmcp-system -l app.kubernetes.io/name=kmcp -f
```

**Output esperado:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
kmcp-controller-manager-66c8764c66-8h5sl   1/1     Running   0          5m
```

---

## Introduccion

**kMCP** (Kubernetes MCP) es una plataforma de desarrollo y plano de control para el Model Context Protocol (MCP). Su proposito principal es simplificar la transicion de servidores MCP desde prototipos locales hacia entornos de produccion en Kubernetes.

### Problema que Resuelve

Los servidores MCP tradicionales utilizan transporte **stdio** (standard input/output), lo cual funciona bien en desarrollo local pero presenta desafios en Kubernetes:

- Los contenedores no pueden comunicarse directamente via stdio entre pods
- Se requiere exponer el servidor MCP via HTTP/SSE para clientes remotos
- La gestion del ciclo de vida del servidor MCP requiere configuracion adicional

### Solucion de kMCP

kMCP proporciona:

1. **Transport Adapter**: Un sidecar que convierte la comunicacion stdio a HTTP/SSE
2. **Controller**: Operador de Kubernetes que gestiona el ciclo de vida de los MCPServers
3. **CLI**: Herramienta de linea de comandos para desarrollo y despliegue

```
┌─────────────────────────────────────────────────────────────────┐
│                        Pod MCPServer                             │
│  ┌─────────────────────┐      ┌─────────────────────────────┐  │
│  │   Init Container    │      │      Main Container         │  │
│  │  Transport Adapter  │◄────►│       MCP Server           │  │
│  │                     │stdio │    (FastMCP/MCP-Go)         │  │
│  │  Puerto HTTP :3000  │      │                             │  │
│  └─────────────────────┘      └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
              │
              │ HTTP/SSE
              ▼
       ┌──────────────┐
       │   Service    │
       │   ClusterIP  │
       └──────────────┘
              │
              ▼
       ┌──────────────┐
       │    kagent    │
       │    Agent     │
       └──────────────┘
```

---

## Arquitectura de kMCP

### Componentes Principales

| Componente | Descripcion |
|------------|-------------|
| **kmcp-controller-manager** | Operador que reconcilia recursos MCPServer |
| **Transport Adapter** | Sidecar que convierte stdio a HTTP |
| **MCPServer CRD** | Custom Resource Definition para declarar servidores MCP |
| **CLI kmcp** | Herramienta de desarrollo y despliegue |

### Flujo de Trabajo

```
1. Usuario crea MCPServer CR
         │
         ▼
2. Controller detecta el nuevo recurso
         │
         ▼
3. Controller crea:
   - Deployment (con transport adapter + MCP server)
   - Service (ClusterIP para exponer HTTP)
   - ServiceAccount (para el pod)
         │
         ▼
4. Pod inicia con dos contenedores:
   - Init: Transport Adapter (puerto 3000)
   - Main: MCP Server (stdio)
         │
         ▼
5. Transport Adapter conecta al MCP Server via stdio
   y expone endpoint HTTP/SSE
         │
         ▼
6. kagent Agent se conecta via RemoteMCPServer
```

---

## Recursos de Kubernetes Creados Durante la Instalacion

Al instalar kMCP con Helm, se crean los siguientes recursos:

### 1. CustomResourceDefinition (CRD)

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: mcpservers.kagent.dev
spec:
  group: kagent.dev
  names:
    kind: MCPServer
    listKind: MCPServerList
    plural: mcpservers
    singular: mcpserver
    categories:
    - kagent
  scope: Namespaced
  versions:
  - name: v1alpha1
```

**Proposito**: Define el esquema del recurso MCPServer que los usuarios pueden crear.

### 2. Deployment (Controller Manager)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kmcp-controller-manager
  namespace: kmcp-system
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: manager
        image: ghcr.io/kagent-dev/kmcp/controller:latest
        command: ["/manager"]
        args:
        - --leader-elect
        - --health-probe-bind-address=:8081
        - --metrics-bind-address=:8443
        - --metrics-secure
        ports:
        - containerPort: 8443  # Metrics
        - containerPort: 8081  # Health
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8081
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8081
        resources:
          limits:
            cpu: 500m
            memory: 128Mi
          requests:
            cpu: 10m
            memory: 64Mi
```

**Proposito**: Ejecuta el controlador que gestiona el ciclo de vida de los MCPServers.

### 3. ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kmcp-controller-manager
  namespace: kmcp-system
automountServiceAccountToken: true
```

**Proposito**: Identidad del controller para interactuar con la API de Kubernetes.

### 4. ClusterRole (Manager Role)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kmcp-manager-role
rules:
# Permisos para recursos core
- apiGroups: [""]
  resources:
  - configmaps
  - services
  - serviceaccounts
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]

# Permisos para deployments
- apiGroups: ["apps"]
  resources:
  - deployments
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]

# Permisos para MCPServer CRD
- apiGroups: ["kagent.dev"]
  resources:
  - mcpservers
  - mcpservers/finalizers
  - mcpservers/status
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
```

**Proposito**: Otorga permisos al controller para crear/gestionar recursos relacionados con MCPServers.

### 5. ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kmcp-manager-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kmcp-manager-role
subjects:
- kind: ServiceAccount
  name: kmcp-controller-manager
  namespace: kmcp-system
```

**Proposito**: Vincula el ClusterRole al ServiceAccount del controller.

### 6. Role (Leader Election)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kmcp-leader-election-role
  namespace: kmcp-system
rules:
# Para ConfigMaps (leader election lock)
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Para Leases (mecanismo preferido de leader election)
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Para Events (logging de leader election)
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
```

**Proposito**: Permite la eleccion de lider cuando hay multiples replicas del controller.

### 7. RoleBinding (Leader Election)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kmcp-leader-election-rolebinding
  namespace: kmcp-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kmcp-leader-election-role
subjects:
- kind: ServiceAccount
  name: kmcp-controller-manager
  namespace: kmcp-system
```

### 8. ClusterRole (Metrics Reader)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kmcp-metrics-reader
rules:
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
```

**Proposito**: Permite a Prometheus scrape de metricas del controller.

### 9. ClusterRole (Metrics Auth)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kmcp-metrics-auth-role
rules:
- apiGroups: ["authentication.k8s.io"]
  resources: ["tokenreviews"]
  verbs: ["create"]
- apiGroups: ["authorization.k8s.io"]
  resources: ["subjectaccessreviews"]
  verbs: ["create"]
```

**Proposito**: Permite autenticacion segura para el endpoint de metricas.

### 10. Service (Metrics)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kmcp-controller-manager-metrics-service
  namespace: kmcp-system
spec:
  type: ClusterIP
  ports:
  - name: https
    port: 8443
    targetPort: 8443
  selector:
    app.kubernetes.io/name: kmcp
```

**Proposito**: Expone metricas del controller para Prometheus.

---

## CRD MCPServer - Especificacion Completa

### Estructura General

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: mi-mcp-server
  namespace: default
spec:
  # Tipo de transporte (requerido)
  transportType: stdio | http

  # Configuracion del despliegue (requerido)
  deployment:
    # ... ver detalles abajo

  # Configuracion para transporte stdio
  stdioTransport: {}

  # Configuracion para transporte HTTP
  httpTransport:
    path: /mcp
    targetPort: 8080
```

### spec.deployment - Configuracion Completa

| Campo | Tipo | Requerido | Default | Descripcion |
|-------|------|-----------|---------|-------------|
| `image` | string | Si | - | Imagen del contenedor MCP server |
| `cmd` | string | No | - | Comando a ejecutar en el contenedor |
| `args` | []string | No | - | Argumentos para el comando |
| `port` | integer | No | 3000 | Puerto donde escucha el MCP server |
| `env` | map[string]string | No | - | Variables de entorno |
| `secretRefs` | []LocalObjectReference | No | - | Secrets a montar como volumenes |
| `configMapRefs` | []LocalObjectReference | No | - | ConfigMaps a montar como volumenes |
| `volumes` | []Volume | No | - | Volumenes personalizados |
| `volumeMounts` | []VolumeMount | No | - | Montajes de volumenes |
| `serviceAccount` | ServiceAccountConfig | No | - | Configuracion del ServiceAccount |

### spec.deployment.serviceAccount

```yaml
spec:
  deployment:
    serviceAccount:
      annotations:
        # Para AWS IRSA
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/mi-rol"
        eks.amazonaws.com/sts-regional-endpoints: "true"
        # Para GCP Workload Identity
        iam.gke.io/gcp-service-account: "mi-sa@proyecto.iam.gserviceaccount.com"
        # Para Azure Workload Identity
        azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"
      labels:
        team: platform
        component: mcp-server
```

### spec.httpTransport

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `path` | string | Ruta donde se sirve el endpoint MCP |
| `targetPort` | int32 | Puerto HTTP del servidor MCP |

### spec.stdioTransport

```yaml
spec:
  stdioTransport: {}  # Objeto vacio, la configuracion se maneja automaticamente
```

### Status del MCPServer

```yaml
status:
  conditions:
  - type: Ready
    status: "True"
    reason: DeploymentReady
    message: "MCPServer deployment is ready"
    lastTransitionTime: "2024-01-15T10:30:00Z"
  observedGeneration: 1
```

**Tipos de Condicion**:
- `Accepted`: El recurso ha sido validado
- `ResolvedRefs`: Las referencias (secrets, configmaps) se han resuelto
- `Programmed`: El deployment ha sido creado
- `Ready`: El MCPServer esta listo para recibir conexiones

---

## Tipos de Transporte

### Transporte stdio (Recomendado)

Este es el transporte mas comun para servidores MCP. kMCP automaticamente:

1. Despliega un **Transport Adapter** como init container
2. Conecta el adapter al MCP server via stdio
3. Expone un endpoint HTTP en el puerto 3000

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: filesystem-server
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: ghcr.io/modelcontextprotocol/servers/filesystem:latest
    cmd: /usr/local/bin/mcp-server-filesystem
    args:
    - /data
    port: 3000
```

**Diagrama de flujo stdio**:
```
Cliente HTTP ──► Transport Adapter ──stdin──► MCP Server
                                    ◄─stdout─
```

### Transporte HTTP

Para servidores MCP que ya exponen un endpoint HTTP nativo:

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: http-mcp-server
spec:
  transportType: http
  httpTransport:
    path: /mcp
    targetPort: 8080
  deployment:
    image: mi-registro/mi-mcp-server:v1
    port: 8080
```

**Nota**: En transporte HTTP, no se despliega el Transport Adapter.

---

## Configuracion del Helm Chart

### Instalacion

```bash
# Agregar repositorio
helm repo add kmcp https://kagent-dev.github.io/kmcp

# Instalar CRDs
helm install kmcp-crds kmcp/kmcp-crds

# Instalar controller
helm install kmcp kmcp/kmcp -n kmcp-system --create-namespace
```

### Valores Configurables (values.yaml)

```yaml
# Override del nombre
nameOverride: ""
fullnameOverride: ""
namespaceOverride: ""

# Configuracion de imagen
image:
  repository: ghcr.io/kagent-dev/kmcp/controller
  pullPolicy: IfNotPresent
  # tag: "" # Por defecto usa appVersion del chart

# Secrets para registros privados
imagePullSecrets: []

# Configuracion del Controller
controller:
  # Numero de replicas
  replicaCount: 1

  # Leader Election (para HA)
  leaderElection:
    enabled: true

  # Health Probes
  healthProbe:
    bindAddress: ":8081"
    livenessProbe:
      initialDelaySeconds: 15
      periodSeconds: 20
    readinessProbe:
      initialDelaySeconds: 5
      periodSeconds: 10

  # Metricas Prometheus
  metrics:
    enabled: true
    bindAddress: ":8443"
    secureServing: true

  # Variables de entorno adicionales
  env: []

# Annotations para pods
podAnnotations: {}

# Security Context del Pod
podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

# Security Context del Contenedor
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - "ALL"

# Recursos
resources:
  limits:
    cpu: 500m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 64Mi

# Scheduling
nodeSelector: {}
tolerations: []
affinity: {}

# ServiceAccount
serviceAccount:
  create: true
  annotations: {}
  name: ""

# RBAC
rbac:
  create: true

# Service para metricas
service:
  type: ClusterIP
  port: 8443
  targetPort: 8443
```

### Ejemplo: Alta Disponibilidad

```yaml
# values-ha.yaml
controller:
  replicaCount: 3
  leaderElection:
    enabled: true

resources:
  limits:
    cpu: 1000m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: kmcp
        topologyKey: kubernetes.io/hostname
```

---

## Ejemplos Practicos

### Ejemplo 1: MCP Server de Filesystem

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: filesystem-mcp
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: ghcr.io/modelcontextprotocol/servers/filesystem:latest
    cmd: /usr/local/bin/mcp-server-filesystem
    args:
    - /data
    port: 3000
    volumes:
    - name: data
      persistentVolumeClaim:
        claimName: mcp-data-pvc
    volumeMounts:
    - name: data
      mountPath: /data
```

### Ejemplo 2: MCP Server con AWS IRSA

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: aws-s3-mcp
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: mi-registro/mcp-s3-server:v1
    cmd: /usr/local/bin/mcp-s3
    args:
    - --bucket
    - mi-bucket
    port: 3000
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/mcp-s3-role"
        eks.amazonaws.com/sts-regional-endpoints: "true"
      labels:
        team: data-platform
        component: mcp-server
```

### Ejemplo 3: MCP Server con Secrets

```yaml
# Primero crear el Secret
apiVersion: v1
kind: Secret
metadata:
  name: api-credentials
  namespace: mcp-servers
type: Opaque
stringData:
  API_KEY: "mi-api-key-secreta"
  API_SECRET: "mi-api-secret"
---
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: api-mcp-server
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: mi-registro/mcp-api-server:v1
    cmd: /app/mcp-server
    port: 3000
    secretRefs:
    - name: api-credentials
    env:
      LOG_LEVEL: "debug"
```

### Ejemplo 4: MCP Server con ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-config
  namespace: mcp-servers
data:
  config.yaml: |
    server:
      timeout: 30s
      max_connections: 100
    features:
      caching: true
      metrics: true
---
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: configured-mcp
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: mi-registro/mcp-server:v1
    cmd: /app/mcp-server
    args:
    - --config
    - /config/config.yaml
    port: 3000
    configMapRefs:
    - name: mcp-config
```

### Ejemplo 5: MCP Server HTTP Nativo

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: http-native-mcp
  namespace: mcp-servers
spec:
  transportType: http
  httpTransport:
    path: /v1/mcp
    targetPort: 8080
  deployment:
    image: mi-registro/mcp-http-server:v1
    port: 8080
    env:
      SERVER_PORT: "8080"
      MCP_PATH: "/v1/mcp"
```

### Ejemplo 6: MCP Server con Volumenes Personalizados

```yaml
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: advanced-mcp
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: mi-registro/mcp-server:v1
    cmd: /app/mcp-server
    port: 3000
    volumes:
    # Volumen temporal
    - name: cache
      emptyDir:
        sizeLimit: 1Gi
    # Volumen desde PVC
    - name: data
      persistentVolumeClaim:
        claimName: mcp-data
    # Volumen desde Secret
    - name: tls-certs
      secret:
        secretName: mcp-tls
    volumeMounts:
    - name: cache
      mountPath: /tmp/cache
    - name: data
      mountPath: /data
    - name: tls-certs
      mountPath: /etc/tls
      readOnly: true
```

---

## Integracion con kagent

### Conexion via RemoteMCPServer

Una vez desplegado un MCPServer con kMCP, se puede conectar desde kagent usando RemoteMCPServer:

```yaml
# MCPServer desplegado con kMCP
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: mi-mcp-server
  namespace: mcp-servers
spec:
  transportType: stdio
  stdioTransport: {}
  deployment:
    image: mi-registro/mcp-server:v1
    cmd: /app/mcp-server
    port: 3000
---
# RemoteMCPServer en kagent
apiVersion: kagent.dev/v1alpha1
kind: RemoteMCPServer
metadata:
  name: mi-mcp-remote
  namespace: kagent-system
spec:
  transport:
    type: sse
    url: http://mi-mcp-server.mcp-servers.svc.cluster.local:3000/sse
---
# Agent que usa el MCP Server
apiVersion: kagent.dev/v1alpha1
kind: Agent
metadata:
  name: mi-agente
  namespace: kagent-system
spec:
  modelConfigRef:
    name: anthropic-claude
  systemPrompt: "Eres un asistente que puede usar herramientas MCP"
  remoteMcpServers:
  - name: mi-mcp-remote
```

### Diagrama de Integracion

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          kagent-system namespace                         │
│                                                                          │
│   ┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐ │
│   │    Agent    │────►│  RemoteMCPServer │────►│  Service (external) │ │
│   │             │     │   transport: sse │     │                     │ │
│   └─────────────┘     └──────────────────┘     └─────────────────────┘ │
│                                                           │             │
└───────────────────────────────────────────────────────────│─────────────┘
                                                            │
                                                            │ HTTP/SSE
                                                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         mcp-servers namespace                            │
│                                                                          │
│   ┌──────────────────┐     ┌─────────────────────────────────────────┐ │
│   │     Service      │────►│               Pod MCPServer              │ │
│   │  mi-mcp-server   │     │  ┌────────────────┐  ┌───────────────┐  │ │
│   │     :3000        │     │  │Transport Adapter│◄►│  MCP Server  │  │ │
│   └──────────────────┘     │  │    (sidecar)   │  │   (stdio)    │  │ │
│                            │  └────────────────┘  └───────────────┘  │ │
│                            └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### Verificar el Estado del MCPServer

```bash
# Ver todos los MCPServers
kubectl get mcpservers -A

# Ver detalles de un MCPServer
kubectl describe mcpserver mi-mcp-server -n mcp-servers

# Ver condiciones de estado
kubectl get mcpserver mi-mcp-server -n mcp-servers -o jsonpath='{.status.conditions}'
```

### Verificar Logs del Controller

```bash
# Logs del controller
kubectl logs -n kmcp-system -l app.kubernetes.io/name=kmcp -f

# Logs especificos de un MCPServer
kubectl logs -n mcp-servers deployment/mi-mcp-server -c manager
kubectl logs -n mcp-servers deployment/mi-mcp-server -c mcp-server
```

### Problemas Comunes

#### 1. MCPServer no se crea

**Sintoma**: El recurso MCPServer existe pero no se crea el Deployment.

**Solucion**:
```bash
# Verificar que el controller esta corriendo
kubectl get pods -n kmcp-system

# Verificar logs del controller
kubectl logs -n kmcp-system deployment/kmcp-controller-manager -f
```

#### 2. Pod en CrashLoopBackOff

**Sintoma**: El pod del MCPServer esta reiniciandose constantemente.

**Solucion**:
```bash
# Ver logs del contenedor
kubectl logs -n mcp-servers pod/mi-mcp-server-xxx -c mcp-server --previous

# Verificar que la imagen y comando son correctos
kubectl describe pod -n mcp-servers mi-mcp-server-xxx
```

#### 3. Error de Conexion desde kagent

**Sintoma**: El Agent no puede conectarse al MCP Server.

**Solucion**:
```bash
# Verificar que el Service existe
kubectl get svc -n mcp-servers mi-mcp-server

# Probar conectividad desde otro pod
kubectl run test --rm -it --image=curlimages/curl -- \
  curl http://mi-mcp-server.mcp-servers.svc.cluster.local:3000/health

# Verificar la URL en el RemoteMCPServer
kubectl get remotemcpserver mi-mcp-remote -n kagent-system -o yaml
```

#### 4. Secrets no Montados

**Sintoma**: Las variables de entorno del Secret no estan disponibles.

**Solucion**:
```bash
# Verificar que el Secret existe
kubectl get secret api-credentials -n mcp-servers

# Verificar que el MCPServer referencia el secret correctamente
kubectl get mcpserver mi-mcp-server -n mcp-servers -o yaml | grep -A5 secretRefs

# Verificar los volumenes montados en el pod
kubectl describe pod -n mcp-servers mi-mcp-server-xxx | grep -A10 Mounts
```

### Comandos Utiles

```bash
# Ver todos los recursos creados por un MCPServer
kubectl get all -n mcp-servers -l app.kubernetes.io/instance=mi-mcp-server

# Ver eventos relacionados
kubectl get events -n mcp-servers --field-selector involvedObject.name=mi-mcp-server

# Reiniciar el MCPServer
kubectl rollout restart deployment/mi-mcp-server -n mcp-servers

# Ver metricas del controller (si Prometheus esta habilitado)
kubectl port-forward -n kmcp-system svc/kmcp-controller-manager-metrics-service 8443:8443
curl -k https://localhost:8443/metrics
```

---

## Referencia de Recursos Creados por MCPServer

Cuando se crea un MCPServer, el controller automaticamente crea:

| Recurso | Nombre | Proposito |
|---------|--------|-----------|
| Deployment | `{mcpserver-name}` | Ejecuta el MCP server con transport adapter |
| Service | `{mcpserver-name}` | Expone el MCP server via ClusterIP |
| ServiceAccount | `{mcpserver-name}` | Identidad del pod (con annotations personalizadas) |

### Ejemplo de Recursos Generados

Para un MCPServer llamado `filesystem-mcp`:

```bash
kubectl get all -n mcp-servers -l app.kubernetes.io/instance=filesystem-mcp

# Output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# pod/filesystem-mcp-7d4f5b6c8-abc123   1/1     Running   0          5m
#
# NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# service/filesystem-mcp   ClusterIP   10.96.123.456   <none>        3000/TCP   5m
#
# NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/filesystem-mcp   1/1     1            1           5m
```

---

## Comparacion: kMCP vs ToolServer vs RemoteMCPServer

| Caracteristica | kMCP MCPServer | ToolServer (DEPRECADO) | RemoteMCPServer |
|----------------|----------------|------------------------|-----------------|
| Transporte | stdio (convertido a HTTP) o HTTP | stdio o HTTP | HTTP/SSE |
| Despliega pods | Si | Si | No |
| Transport Adapter | Automatico | Manual | N/A |
| ServiceAccount customizable | Si | Limitado | N/A |
| Integracion cloud (IRSA, etc) | Nativa | Compleja | N/A |
| Estado | Activo | Deprecado | Activo |
| Uso | Desplegar MCP servers | N/A | Conectar a MCP existentes |

**Recomendacion**:
- Usa **kMCP MCPServer** para desplegar servidores MCP basados en stdio en Kubernetes
- Usa **RemoteMCPServer** para conectar kagent a servidores MCP ya existentes (desplegados con kMCP u otros)

---

## Recursos Adicionales

- [Documentacion oficial de kMCP](https://kagent.dev/docs/kmcp)
- [Repositorio GitHub](https://github.com/kagent-dev/kmcp)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [FastMCP (Python)](https://github.com/jlowin/fastmcp)
- [MCP Go SDK](https://github.com/mark3labs/mcp-go)
