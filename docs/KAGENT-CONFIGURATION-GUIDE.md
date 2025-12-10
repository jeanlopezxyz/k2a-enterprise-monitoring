# Guia Completa de Configuracion de kagent

Esta guia documenta todos los recursos de Kubernetes que se crean al instalar kagent, asi como todas las opciones de configuracion disponibles para los CRDs.

## Tabla de Contenidos

1. [Metodos de Instalacion](#metodos-de-instalacion)
   - [Quick Start con CLI](#quick-start-con-cli)
   - [Instalacion con Helm](#instalacion-con-helm)
   - [Instalacion con ArgoCD](#instalacion-con-argocd)
2. [Arquitectura de kagent](#arquitectura-de-kagent)
3. [Recursos de Kubernetes Creados](#recursos-de-kubernetes-creados)
4. [Custom Resource Definitions (CRDs)](#custom-resource-definitions-crds)
5. [Configuracion de Agent](#configuracion-de-agent)
6. [Configuracion de ModelConfig](#configuracion-de-modelconfig)
7. [Configuracion de RemoteMCPServer](#configuracion-de-remotemcpserver)
8. [Configuracion de Memory](#configuracion-de-memory)
9. [Interaccion entre Agentes y MCP Servers](#interaccion-entre-agentes-y-mcp-servers)
10. [Usando Kubernetes Service como MCP Server](#usando-kubernetes-service-como-mcp-server)
11. [Configuracion de ToolServer (DEPRECADO)](#configuracion-de-toolserver-deprecado)
12. [Ejemplos Practicos](#ejemplos-practicos)
13. [Configuracion de Skills (Container Images)](#configuracion-de-skills-container-images)
14. [Configuracion de Seguridad](#configuracion-de-seguridad)
15. [Referencia Rapida](#referencia-rapida)

---

## Metodos de Instalacion

kagent ofrece multiples formas de instalacion segun tus necesidades:

| Metodo | Caso de Uso | Perfiles Disponibles |
|--------|-------------|---------------------|
| **CLI (kagent)** | Desarrollo rapido, demos | `demo`, `minimal` |
| **Helm** | Produccion, personalizacion | N/A (configuracion via values) |
| **ArgoCD** | GitOps, produccion enterprise | N/A (configuracion via values) |

### Prerequisitos

Antes de comenzar, asegurate de tener instalados:

- **kubectl** - Para interactuar con tu cluster
- **Helm** - Para instalacion via Helm/ArgoCD
- **kind** (opcional) - Para crear un cluster local de pruebas
- **API Key de OpenAI** u otro proveedor LLM

---

### Quick Start con CLI

La forma mas rapida de comenzar con kagent es usando el CLI oficial.

#### 1. Instalar el CLI

```bash
# macOS con Homebrew
brew install kagent

# Linux/macOS con script
curl https://raw.githubusercontent.com/kagent-dev/kagent/refs/heads/main/scripts/get-kagent | bash
```

#### 2. Configurar API Key

```bash
export OPENAI_API_KEY="tu-api-key-aqui"
```

#### 3. Instalar kagent en el Cluster

```bash
# Perfil demo: incluye agentes y tools pre-configurados
kagent install --profile demo

# Perfil minimal: solo el controlador, sin agentes pre-configurados
kagent install --profile minimal
```

**Perfiles disponibles:**

| Perfil | Descripcion |
|--------|-------------|
| `demo` | Incluye agentes pre-configurados (k8s-agent, helm-agent, observability-agent, istio-agent), tools y configuraciones de ejemplo |
| `minimal` | Solo instala el controlador y CRDs, sin agentes ni tools adicionales |

#### 4. Acceder al Dashboard

```bash
kagent dashboard
# Abre http://localhost:8082
```

#### 5. Usar el CLI

```bash
# Ver agentes disponibles
kagent get agent

# Invocar un agente
kagent invoke -t "Que pods hay en mi cluster?" --agent helm-agent

# Ver otros comandos
kagent help
```

---

### Instalacion con Helm

Para entornos de produccion o cuando necesitas mayor control sobre la configuracion.

> **Nota:** kagent usa un registro OCI (ghcr.io) en lugar de un repositorio Helm tradicional.

#### 1. Crear el Namespace

```bash
kubectl create namespace kagent-system
```

#### 2. Crear el Secret con API Key

```bash
kubectl create secret generic kagent-openai \
  --namespace kagent-system \
  --from-literal=api-key="${OPENAI_API_KEY}"
```

#### 3. Instalar CRDs

```bash
# Primero instalar los CRDs
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent-system \
  --version 0.7.6
```

#### 4. Instalar kagent

```bash
# Instalacion basica
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent-system \
  --version 0.7.6 \
  --set modelConfig.apiKeySecret=kagent-openai

# Instalacion con valores personalizados
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent-system \
  --version 0.7.6 \
  -f values.yaml
```

#### Ejemplo de values.yaml

```yaml
# Namespace para kagent
namespace: kagent-system

# Configuracion del controlador
controller:
  image:
    repository: ghcr.io/kagent-dev/kagent/controller
    tag: latest
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# UI de kagent
ui:
  enabled: true
  service:
    type: ClusterIP
    port: 8080

# ModelConfig por defecto
modelConfig:
  provider: OpenAI
  model: gpt-4o
  apiKeySecret: kagent-openai
  apiKeySecretKey: api-key

# Agentes pre-configurados
agents:
  k8sAgent:
    enabled: true
  helmAgent:
    enabled: true
  observabilityAgent:
    enabled: false

# Tools integrados
tools:
  kubernetes:
    enabled: true
```

---

### Instalacion con ArgoCD

Para entornos GitOps y produccion enterprise, kagent se puede desplegar usando ArgoCD.

> **Nota:** kagent usa un registro OCI (ghcr.io) en lugar de un repositorio Helm tradicional.
> Se requiere instalar primero los CRDs y luego el chart principal.

#### Prerequisitos: Instalar CRDs

Antes de instalar kagent, debes instalar los CRDs. Crea esta Application primero:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagent-crds
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/kagent-dev/kagent/helm
    chart: kagent-crds
    targetRevision: 0.7.6
  destination:
    server: https://kubernetes.default.svc
    namespace: kagent-system
  syncPolicy:
    automated:
      prune: false  # No eliminar CRDs automaticamente
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

#### Opcion 1: Application Simple

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagent
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/kagent-dev/kagent/helm
    chart: kagent
    targetRevision: 0.7.6
    helm:
      values: |
        namespace: kagent-system

        controller:
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi

        ui:
          enabled: true
          service:
            type: ClusterIP

        modelConfig:
          provider: OpenAI
          model: gpt-4o
          apiKeySecret: kagent-openai
          apiKeySecretKey: api-key

  destination:
    server: https://kubernetes.default.svc
    namespace: kagent-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

#### Opcion 2: ApplicationSet para Multi-Cluster

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kagent
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            kagent-enabled: "true"
  template:
    metadata:
      name: kagent-{{name}}
    spec:
      project: default
      source:
        repoURL: ghcr.io/kagent-dev/kagent/helm
        chart: kagent
        targetRevision: 0.7.6
        helm:
          valueFiles:
            - values-{{name}}.yaml
      destination:
        server: '{{server}}'
        namespace: kagent-system
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

#### Opcion 3: Desde Repositorio Git (Recomendado para GitOps)

**Estructura del repositorio:**

```
├── argocd/
│   └── applications/
│       └── kagent.yaml
├── helm/
│   └── kagent/
│       ├── Chart.yaml
│       └── values/
│           ├── base.yaml
│           ├── dev.yaml
│           └── prod.yaml
└── secrets/
    └── kagent-secrets.yaml  # SealedSecret o ExternalSecret
```

**Application que usa repositorio Git:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kagent
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/tu-org/tu-repo.git
    path: helm/kagent
    targetRevision: main
    helm:
      valueFiles:
        - values/base.yaml
        - values/prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: kagent-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

#### Configuracion del Secret con External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kagent-openai
  namespace: kagent-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend  # o aws-secrets-manager, etc.
    kind: ClusterSecretStore
  target:
    name: kagent-openai
    creationPolicy: Owner
  data:
    - secretKey: api-key
      remoteRef:
        key: kagent/openai
        property: api-key
```

#### Configuracion del Secret con SealedSecrets

```bash
# Crear el secret y sellarlo
kubectl create secret generic kagent-openai \
  --namespace kagent-system \
  --from-literal=api-key="${OPENAI_API_KEY}" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > kagent-sealed-secret.yaml
```

#### AppProject para kagent

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: kagent
  namespace: argocd
spec:
  description: kagent AI Agent Framework
  sourceRepos:
    - ghcr.io/kagent-dev/kagent/helm/*
    - https://github.com/tu-org/tu-repo.git
  destinations:
    - namespace: kagent-system
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
  namespaceResourceWhitelist:
    - group: ''
      kind: '*'
    - group: apps
      kind: '*'
    - group: kagent.dev
      kind: '*'
```

---

### Comparacion de Metodos de Instalacion

| Caracteristica | CLI | Helm | ArgoCD |
|----------------|-----|------|--------|
| **Rapidez** | Muy rapido | Moderado | Moderado |
| **Personalizacion** | Limitada | Alta | Muy alta |
| **GitOps** | No | Manual | Si |
| **Multi-cluster** | No | Manual | Si (ApplicationSet) |
| **Perfiles** | `demo`, `minimal` | Via values | Via values |
| **Recomendado para** | Desarrollo, demos | Produccion simple | Produccion enterprise |

---

### Verificar la Instalacion

Independientemente del metodo de instalacion, verifica que todo funciona:

```bash
# Ver pods de kagent
kubectl get pods -n kagent-system

# Ver CRDs instalados
kubectl get crd | grep kagent

# Ver agentes disponibles
kubectl get agents -n kagent-system

# Ver ModelConfigs
kubectl get modelconfigs -n kagent-system

# Ver RemoteMCPServers
kubectl get remotemcpservers -n kagent-system
```

**Output esperado:**

```
NAME                                READY   STATUS    RESTARTS   AGE
kagent-controller-xxxx-yyyy         1/1     Running   0          5m
kagent-ui-xxxx-yyyy                 1/1     Running   0          5m
kagent-tools-xxxx-yyyy              1/1     Running   0          5m
```

---

## Arquitectura de kagent

kagent es un operador de Kubernetes que permite desplegar y gestionar agentes de IA con acceso a herramientas (tools) mediante el protocolo MCP (Model Context Protocol).

```
+------------------+     +-------------------+     +------------------+
|                  |     |                   |     |                  |
|   kagent UI      |---->|  kagent Controller|---->|  Agent Pods      |
|   (Frontend)     |     |  (Operador K8s)   |     |  (LLM Workers)   |
|                  |     |                   |     |                  |
+------------------+     +-------------------+     +------------------+
                                  |
                                  v
                         +------------------+
                         |                  |
                         |   MCP Servers    |
                         |   (Tools/APIs)   |
                         |                  |
                         +------------------+
```

---

## Recursos de Kubernetes Creados

Al instalar kagent con Helm, se crean los siguientes recursos:

### 1. Custom Resource Definitions (CRDs)

| CRD | Grupo | Descripcion |
|-----|-------|-------------|
| `agents.kagent.dev` | kagent.dev | Define agentes de IA con tools y configuracion de modelo |
| `modelconfigs.kagent.dev` | kagent.dev | Configuracion de proveedores LLM (OpenAI, Anthropic, etc.) |
| `remotemcpservers.kagent.dev` | kagent.dev | Conexion a servidores MCP remotos |
| `toolservers.kagent.dev` | kagent.dev | (Legacy) Configuracion de servidores de herramientas |
| `memories.kagent.dev` | kagent.dev | Configuracion de memoria vectorial |

**Proposito:** Los CRDs extienden la API de Kubernetes para permitir la creacion de recursos personalizados de kagent.

### 2. Controller (Operador)

| Recurso | Nombre | Descripcion |
|---------|--------|-------------|
| **Deployment** | `kagent-controller` | Despliega el controlador que reconcilia los CRDs |
| **Service** | `kagent-controller` | Expone el API del controlador (puerto 8083) |
| **ServiceAccount** | `kagent-controller` | Identidad del controlador para RBAC |
| **ConfigMap** | `kagent-controller` | Configuracion del controlador (base de datos, logging, etc.) |

**Proposito:** El Controller es el cerebro de kagent. Observa los CRDs y:
- Crea/actualiza Deployments para cada Agent
- Conecta Agents con MCP Servers
- Gestiona el ciclo de vida de los recursos

### 3. RBAC (Control de Acceso)

| Recurso | Nombre | Descripcion |
|---------|--------|-------------|
| **ClusterRole** | `kagent-getter-role` | Permisos de lectura sobre CRDs y recursos K8s |
| **ClusterRole** | `kagent-writer-role` | Permisos de escritura sobre CRDs y recursos K8s |
| **ClusterRoleBinding** | `kagent-getter-binding` | Vincula getter-role al ServiceAccount |
| **ClusterRoleBinding** | `kagent-writer-binding` | Vincula writer-role al ServiceAccount |
| **Role** | `kagent-leader-election` | Permisos para leader election |
| **RoleBinding** | `kagent-leader-election` | Vincula role de leader election |

**Proposito:** El RBAC permite al controlador:
- Leer/escribir CRDs de kagent
- Crear/gestionar Deployments, Services, ConfigMaps, Secrets
- Leer recursos de Kubernetes (pods, services, etc.) para los tools

### 4. UI (Interfaz Web)

| Recurso | Nombre | Descripcion |
|---------|--------|-------------|
| **Deployment** | `kagent-ui` | Frontend web para interactuar con agentes |
| **Service** | `kagent-ui` | Expone la UI (puerto 8080) |
| **ServiceAccount** | `kagent-ui` | Identidad de la UI |

**Proposito:** La UI proporciona:
- Chat con agentes
- Gestion de agentes, ModelConfigs y Tools
- Visualizacion de sesiones y logs

### 5. ModelConfig por Defecto

| Recurso | Nombre | Descripcion |
|---------|--------|-------------|
| **Secret** | `kagent-openai` (u otro) | Almacena API keys de proveedores LLM |
| **ModelConfig** | `default-model-config` | Configuracion del modelo por defecto |

**Proposito:** Proporciona una configuracion LLM lista para usar.

### 6. Tools Integrados

| Recurso | Nombre | Descripcion |
|---------|--------|-------------|
| **Deployment** | `kagent-tools` | Servidor de herramientas integradas |
| **Service** | `kagent-tools` | Expone las tools (puerto 8084) |
| **RemoteMCPServer/ToolServer** | `kagent-tool-server` | CRD que referencia el servidor de tools |

**Proposito:** Proporciona herramientas basicas como:
- `k8s_get_resources` - Obtener recursos de Kubernetes
- `k8s_describe_resource` - Describir recursos
- `k8s_apply_manifest` - Aplicar manifiestos

### 7. Agentes Pre-configurados (Opcionales)

Al habilitar agentes en values.yaml, se crean:

| Recurso | Ejemplo | Descripcion |
|---------|---------|-------------|
| **Agent** | `k8s-agent` | Agente para gestion de Kubernetes |
| **Agent** | `promql-agent` | Agente para consultas PromQL |
| **Agent** | `helm-agent` | Agente para gestion de Helm |
| **Agent** | `observability-agent` | Agente para observabilidad |

---

## Flujo de Reconciliacion

Cuando creas un recurso Agent:

```
1. Usuario crea Agent CR
         |
         v
2. Controller detecta el nuevo Agent
         |
         v
3. Controller valida la configuracion
   - Verifica ModelConfig existe
   - Verifica RemoteMCPServers existen
         |
         v
4. Controller crea recursos derivados:
   - Deployment para el Agent
   - ConfigMap con configuracion del agente
   - Service si es necesario
         |
         v
5. Controller actualiza status del Agent
   - Ready: true/false
   - Accepted: true/false
```

---

## Custom Resource Definitions (CRDs)

### Resumen de CRDs

| CRD | API Version | Short Names | Estado | Descripcion |
|-----|-------------|-------------|--------|-------------|
| Agent | `kagent.dev/v1alpha2` | - | **Activo** | Agentes de IA |
| ModelConfig | `kagent.dev/v1alpha2` | `mc` | **Activo** | Configuracion de LLM |
| RemoteMCPServer | `kagent.dev/v1alpha2` | `rmcps` | **Activo** | Servidores MCP remotos |
| Memory | `kagent.dev/v1alpha1` | - | **Activo** | Memoria vectorial |
| ToolServer | `kagent.dev/v1alpha1` | `ts` | **DEPRECADO** | Reemplazado por RemoteMCPServer |

---

## Configuracion de Agent

### Tipos de Agent

kagent soporta dos tipos de agentes que se adaptan a diferentes casos de uso:

| Tipo | Descripcion | Caso de Uso |
|------|-------------|-------------|
| `Declarative` | Gestionado completamente por kagent | Agentes estandar donde kagent maneja el deployment, ConfigMaps y Services automaticamente |
| `BYO` (Bring Your Own) | El usuario proporciona su propia imagen de agente | Agentes personalizados con logica custom o integracion con frameworks existentes |

#### Agente Declarative
El controlador de kagent crea automaticamente:
- **Deployment** para ejecutar el agente
- **ConfigMap** con la configuracion del agente
- **Service** para exponer el agente (si es necesario)

```yaml
spec:
  type: Declarative
  description: "Mi agente gestionado"
  declarative:
    modelConfig: mi-modelo
    systemMessage: "Eres un asistente experto"
    tools: [...]
```

#### Agente BYO (Bring Your Own)
Util cuando tienes una imagen de agente personalizada o logica de negocio especifica:

```yaml
spec:
  type: BYO
  description: "Agente con imagen custom"
  byo:
    deployment:
      image: mi-registry.com/mi-agente:v1.0.0
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
```

### Especificacion Completa del Agent (v1alpha2)

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: mi-agente
  namespace: kagent
spec:
  # Tipo de agente: Declarative o BYO
  type: Declarative

  # ============================================
  # CONFIGURACION PARA AGENTES DECLARATIVOS
  # ============================================
  declarative:
    # Descripcion del agente (requerido)
    description: "Descripcion de lo que hace el agente"

    # ----------------------------------------
    # SYSTEM MESSAGE
    # ----------------------------------------
    # Opcion 1: Mensaje directo
    systemMessage: "Eres un asistente experto en Kubernetes."

    # Opcion 2: Desde ConfigMap o Secret
    systemMessageFrom:
      type: ConfigMap  # o Secret
      name: mis-prompts
      key: system-prompt

    # ----------------------------------------
    # MODELO DE IA
    # ----------------------------------------
    # Referencia a ModelConfig (mismo namespace o namespace/nombre)
    modelConfig: mi-modelo-config

    # Streaming de respuestas (default: true)
    stream: true

    # ----------------------------------------
    # EJECUCION DE CODIGO
    # ----------------------------------------
    # Permite ejecutar bloques de Python (sandboxed)
    executeCodeBlocks: false

    # ----------------------------------------
    # HERRAMIENTAS (TOOLS)
    # ----------------------------------------
    tools:
      # Tipo 1: MCP Server (RemoteMCPServer)
      - type: McpServer
        mcpServer:
          name: mi-mcp-server
          kind: RemoteMCPServer
          apiGroup: kagent.dev  # Requerido para RemoteMCPServer
          # Lista opcional de tools especificas
          toolNames:
            - tool_1
            - tool_2
        # Headers de autenticacion
        headersFrom:
          - name: Authorization
            valueFrom:
              type: Secret
              name: mi-secret
              key: token

      # Tipo 2: MCP Server (Service de Kubernetes)
      - type: McpServer
        mcpServer:
          name: mi-mcp-service
          kind: Service  # Usa Service de K8s directamente
          toolNames:
            - tool_1

      # Tipo 3: Otro Agent como herramienta (agentes anidados)
      - type: Agent
        agent:
          name: agente-especialista  # o namespace/nombre
        headersFrom:
          - name: X-Custom-Header
            value: "valor-estatico"

    # ----------------------------------------
    # CONFIGURACION A2A (Agent-to-Agent)
    # ----------------------------------------
    a2aConfig:
      skills:
        - id: consulta-prometheus
          name: Consulta Prometheus
          description: "Ejecuta consultas PromQL"
          tags:
            - monitoring
            - prometheus
          inputModes:
            - text
          outputModes:
            - text
          examples:
            - "Muestra el uso de CPU del ultimo minuto"

    # ----------------------------------------
    # CONFIGURACION DE DEPLOYMENT
    # ----------------------------------------
    deployment:
      # Replicas del agente
      replicas: 1

      # Labels adicionales para los pods
      labels:
        app.kubernetes.io/team: sre

      # Anotaciones adicionales
      annotations:
        prometheus.io/scrape: "true"

      # Recursos de CPU/Memoria
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 2Gi

      # Seleccion de nodos
      nodeSelector:
        kubernetes.io/os: linux
        node-type: ai-workload

      # Toleraciones para taints
      tolerations:
        - key: "ai-workload"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"

      # Afinidad de pods/nodos
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values:
                      - linux
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: mi-agente
                topologyKey: kubernetes.io/hostname

      # Variables de entorno
      env:
        - name: LOG_LEVEL
          value: "debug"
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: mi-secret
              key: api-key

      # Secretos para pull de imagenes
      imagePullSecrets:
        - name: registry-secret

      # Volumenes personalizados
      volumes:
        - name: config-vol
          configMap:
            name: mi-config

  # ============================================
  # CONFIGURACION PARA AGENTES BYO
  # ============================================
  byo:
    deployment:
      image: mi-registry/mi-agente:v1.0.0
      # Mismas opciones de deployment que declarative
      resources:
        requests:
          cpu: 500m
          memory: 1Gi

  # ============================================
  # SKILLS (Referencias externas)
  # ============================================
  skills:
    refs:
      - mi-skill:latest
```

### Opciones de Tools

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `type` | string | `McpServer` o `Agent` |
| `mcpServer.name` | string | Nombre del recurso MCP |
| `mcpServer.kind` | string | `RemoteMCPServer`, `Service`, `MCPServer` (kmcp) |
| `mcpServer.apiGroup` | string | API group (requerido para `RemoteMCPServer`: `kagent.dev`) |
| `mcpServer.toolNames` | []string | Tools especificos a exponer (opcional) |
| `agent.name` | string | Nombre del Agent a usar como tool |
| `headersFrom` | []ValueRef | Headers de autenticacion |

> **Nota importante sobre `type`:** En la API v1alpha2 de kagent, el valor correcto es `McpServer` (con 'M' mayuscula y 'c' minuscula), no `MCPServer`.

### Opciones de Deployment

| Campo | Tipo | Descripcion | Default |
|-------|------|-------------|---------|
| `replicas` | int32 | Numero de replicas | 1 |
| `labels` | map | Labels adicionales | - |
| `annotations` | map | Anotaciones | - |
| `resources` | ResourceRequirements | CPU/Memoria | - |
| `nodeSelector` | map | Seleccion de nodos | - |
| `tolerations` | []Toleration | Toleraciones | - |
| `affinity` | Affinity | Reglas de afinidad | - |
| `env` | []EnvVar | Variables de entorno | - |
| `imagePullSecrets` | []LocalObjectReference | Secretos de registry | - |
| `volumes` | []Volume | Volumenes | - |

---

## Configuracion de ModelConfig

### Proveedores Soportados

| Proveedor | Descripcion |
|-----------|-------------|
| `OpenAI` | API de OpenAI (GPT-4, etc.) |
| `Anthropic` | API de Anthropic (Claude) |
| `AzureOpenAI` | Azure OpenAI Service |
| `Ollama` | Modelos locales con Ollama |
| `Gemini` | API de Google Gemini |
| `GeminiVertexAI` | Gemini via Google Vertex AI |
| `AnthropicVertexAI` | Claude via Google Vertex AI |

### Especificacion Completa de ModelConfig

```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: mi-modelo
  namespace: kagent
spec:
  # Proveedor del modelo (requerido)
  provider: OpenAI

  # Nombre del modelo (requerido)
  model: gpt-4o

  # ----------------------------------------
  # AUTENTICACION
  # ----------------------------------------
  # Referencia al Secret con API key
  apiKeySecret: mi-secret-openai
  apiKeySecretKey: api-key

  # Headers por defecto para todas las requests
  defaultHeaders:
    User-Agent: "kagent/1.0"
    X-Custom-Header: "valor"

  # ----------------------------------------
  # CONFIGURACION TLS
  # Para conexiones a gateways internos con certificados custom
  # ----------------------------------------
  tls:
    # Deshabilitar verificacion SSL (SOLO para dev/test)
    disableVerify: false

    # Certificado CA personalizado
    caCertSecretRef: mi-ca-cert
    caCertSecretKey: ca.crt

    # Usar SOLO el CA custom (no los del sistema)
    disableSystemCAs: false

  # ----------------------------------------
  # CONFIGURACION ESPECIFICA POR PROVEEDOR
  # Solo usar UNO de los siguientes
  # ----------------------------------------

  # === OpenAI ===
  openAI:
    # Endpoint personalizado (para proxies/gateways)
    baseUrl: "https://api.openai.com"

    # Parametros del modelo
    temperature: "0.7"       # 0-2
    maxTokens: 2048
    topP: "0.95"
    frequencyPenalty: "0"    # -2 a 2
    presencePenalty: "0"     # -2 a 2
    n: 1                     # Numero de completions
    seed: 42                 # Seed para reproducibilidad
    timeout: 30              # Timeout en segundos
    organization: "org-xxx"  # Organization ID

    # Para modelos con razonamiento (o1, etc.)
    reasoningEffort: "low"   # minimal, low, medium, high

  # === Anthropic ===
  anthropic:
    baseUrl: "https://api.anthropic.com"
    temperature: "0.3"
    maxTokens: 4096
    topP: "0.9"
    topK: 40

  # === Azure OpenAI ===
  azureOpenAI:
    azureEndpoint: "https://mi-recurso.openai.azure.com"
    azureDeployment: "mi-deployment"
    apiVersion: "2024-02-01"
    azureAdToken: ""  # Token de Azure AD (opcional)
    temperature: "0.7"
    maxTokens: 1024
    topP: "0.95"

  # === Ollama ===
  ollama:
    host: "http://ollama.ai-tools:11434"
    options:
      temperature: "0.8"
      top_p: "0.9"
      num_ctx: "4096"
      num_gpu: "1"

  # === Gemini ===
  gemini: {}

  # === Gemini Vertex AI ===
  geminiVertexAI:
    projectID: "mi-proyecto-gcp"
    location: "us-central1"
    temperature: "0.7"
    topP: "0.9"
    topK: "40"
    maxOutputTokens: 1024
    candidateCount: 1
    responseMimeType: "text/plain"
    stopSequences:
      - "STOP"
      - "END"

  # === Anthropic Vertex AI ===
  anthropicVertexAI:
    projectID: "mi-proyecto-gcp"
    location: "us-east5"
    temperature: "0.7"
    topP: "0.9"
    topK: "40"
    maxTokens: 4096
    stopSequences:
      - "STOP"
```

### Parametros por Proveedor

#### OpenAI

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `baseUrl` | string | Endpoint de API |
| `temperature` | string | Temperatura de sampling (0-2) |
| `maxTokens` | int | Maximo de tokens a generar |
| `topP` | string | Top-p sampling |
| `frequencyPenalty` | string | Penalizacion de frecuencia |
| `presencePenalty` | string | Penalizacion de presencia |
| `n` | int | Numero de completions |
| `seed` | int | Seed para reproducibilidad |
| `timeout` | int | Timeout en segundos |
| `organization` | string | Organization ID |
| `reasoningEffort` | string | Esfuerzo de razonamiento |

#### Anthropic

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `baseUrl` | string | Endpoint de API |
| `temperature` | string | Temperatura |
| `maxTokens` | int | Maximo de tokens |
| `topP` | string | Top-p sampling |
| `topK` | int | Top-k sampling |

#### Ollama

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `host` | string | URL del servidor Ollama |
| `options` | map | Opciones del modelo |

---

## Configuracion de RemoteMCPServer

RemoteMCPServer permite conectar agentes a servidores MCP remotos que exponen herramientas.

```yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: mi-mcp-server
  namespace: kagent
spec:
  # URL del servidor MCP (requerido)
  url: "http://mcp-server.namespace.svc.cluster.local:8000/mcp"

  # Descripcion del servidor (requerido)
  description: "Mi servidor MCP"

  # Protocolo de comunicacion
  # SSE: Server-Sent Events (legacy)
  # STREAMABLE_HTTP: HTTP con streaming (default)
  protocol: STREAMABLE_HTTP

  # Timeouts
  timeout: "30s"
  sseReadTimeout: "5m0s"

  # Cerrar conexion cuando se cierra
  terminateOnClose: true

  # Headers de autenticacion
  headersFrom:
    # Header con valor estatico
    - name: X-API-Version
      value: "v1"

    # Header desde Secret
    - name: Authorization
      valueFrom:
        type: Secret
        name: mcp-auth-secret
        key: token

    # Header desde ConfigMap
    - name: X-Custom-Config
      valueFrom:
        type: ConfigMap
        name: mcp-config
        key: header-value
```

### Opciones de RemoteMCPServer

| Campo | Tipo | Descripcion | Default |
|-------|------|-------------|---------|
| `url` | string | URL del endpoint MCP | Requerido |
| `description` | string | Descripcion del servidor | Requerido |
| `protocol` | string | `SSE` o `STREAMABLE_HTTP` | `STREAMABLE_HTTP` |
| `timeout` | string | Timeout de request | - |
| `sseReadTimeout` | string | Timeout de lectura SSE | - |
| `terminateOnClose` | bool | Terminar en close | true |
| `headersFrom` | []ValueRef | Headers de autenticacion | - |

### Status de RemoteMCPServer

```yaml
status:
  conditions:
    - type: Accepted
      status: "True"
      reason: ServerReachable
      message: "MCP server is reachable and responding"
  discoveredTools:
    - name: get_metrics
      description: "Obtiene metricas de Prometheus"
    - name: query_logs
      description: "Consulta logs de Loki"
  observedGeneration: 1
```

---

## Configuracion de ToolServer (DEPRECADO)

> **IMPORTANTE: ToolServer esta DEPRECADO desde v1alpha2.**
>
> **Usar en su lugar:**
> - `RemoteMCPServer` - Para servidores MCP remotos (HTTP/SSE)
> - `kmcp MCPServer` - Para servidores MCP stdio en Kubernetes
> - `Service` con anotaciones - Para servicios K8s existentes
>
> ToolServer solo se mantiene por compatibilidad con instalaciones existentes.

```yaml
apiVersion: kagent.dev/v1alpha1
kind: ToolServer
metadata:
  name: mi-toolserver
  namespace: kagent
spec:
  # Descripcion (requerido)
  description: "Mi servidor de herramientas"

  config:
    # Solo UNO de los siguientes puede ser especificado

    # ----------------------------------------
    # STDIO (Ejecucion local)
    # ----------------------------------------
    stdio:
      command: "/usr/local/bin/mcp-server"
      args:
        - "--port"
        - "8080"
      env:
        LOG_LEVEL: "debug"
      envFrom:
        - name: API_KEY
          valueFrom:
            type: Secret
            valueRef: secret-name
            key: api-key
      readTimeoutSeconds: 10

    # ----------------------------------------
    # SSE (Server-Sent Events)
    # ----------------------------------------
    sse:
      url: "http://server:8080/sse"
      timeout: "30s"
      sseReadTimeout: "5m"
      headers:
        X-Custom: "valor"
      headersFrom:
        - name: Auth
          valueFrom:
            type: Secret
            valueRef: auth-secret
            key: token

    # ----------------------------------------
    # STREAMABLE HTTP
    # ----------------------------------------
    streamableHttp:
      url: "http://server:8080/mcp"
      timeout: "30s"
      terminateOnClose: true
      headers:
        X-Custom: "valor"
      headersFrom:
        - name: Auth
          valueFrom:
            type: Secret
            valueRef: auth-secret
            key: token
```

---

## Configuracion de Memory

Memory permite a los agentes acceder a memoria vectorial para RAG (Retrieval-Augmented Generation).

```yaml
apiVersion: kagent.dev/v1alpha1
kind: Memory
metadata:
  name: mi-memoria
  namespace: kagent
spec:
  # Proveedor (actualmente solo Pinecone)
  provider: Pinecone

  # Autenticacion
  apiKeySecretRef: pinecone-secret  # o namespace/nombre
  apiKeySecretKey: api-key

  # Configuracion de Pinecone
  pinecone:
    # Host del indice (requerido)
    indexHost: "https://mi-indice.svc.pinecone.io"

    # Namespace dentro del indice (opcional)
    namespace: "mi-namespace"

    # Numero de resultados a retornar
    topK: 10

    # Umbral minimo de similitud
    scoreThreshold: "0.7"

    # Campos a recuperar
    recordFields:
      - content
      - metadata
      - source
```

### Opciones de Pinecone

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `indexHost` | string | URL del indice Pinecone |
| `namespace` | string | Namespace dentro del indice |
| `topK` | int | Numero de resultados |
| `scoreThreshold` | string | Umbral de similitud |
| `recordFields` | []string | Campos a recuperar |

---

## Interaccion entre Agentes y MCP Servers

### Flujo de Comunicacion

Los agentes de kagent interactuan con herramientas (tools) a traves del protocolo MCP (Model Context Protocol). El flujo es el siguiente:

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Usuario   │────▶│     Agent       │────▶│   MCP Server    │
│   (Chat)    │     │  (LLM Worker)   │     │  (Tools/APIs)   │
└─────────────┘     └─────────────────┘     └─────────────────┘
                           │                        │
                           │  1. User query         │
                           │  2. LLM decide tool    │
                           │  3. Call MCP tool ────▶│
                           │  4. Tool result ◀──────│
                           │  5. LLM format response│
                           ▼
                    ┌─────────────────┐
                    │   Response to   │
                    │     User        │
                    └─────────────────┘
```

### Tipos de MCP Server soportados

kagent soporta **3 formas** de conectar agentes a MCP servers:

| Kind | API Group | Descripcion | Uso Principal |
|------|-----------|-------------|---------------|
| `RemoteMCPServer` | `kagent.dev` | CRD de kagent para MCP HTTP/SSE | Servidores MCP externos o remotos |
| `Service` | - | K8s Service con anotaciones | Servicios MCP ya desplegados en el cluster |
| `MCPServer` | `kmcp.dev` | Recurso de kmcp | Servidores MCP stdio ejecutados via kmcp |

### Ejemplo Completo de Integracion

```yaml
# 1. RemoteMCPServer - Define el servidor MCP
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: prometheus-mcp
  namespace: kagent
spec:
  url: "http://mcp-prometheus.mcp-servers:9081/mcp/sse"
  description: "MCP Server para Prometheus - Consultas PromQL"
  timeout: 30s
  sseReadTimeout: 5m0s
---
# 2. Agent - Usa el MCP Server
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: monitoring-agent
  namespace: kagent
spec:
  type: Declarative
  description: "Agente de monitoreo con Prometheus"
  declarative:
    modelConfig: default-model-config
    stream: true
    systemMessage: |
      Eres un experto en monitoreo de Kubernetes.
      Usa las herramientas de Prometheus para responder consultas.
    tools:
      - type: McpServer
        mcpServer:
          name: prometheus-mcp
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - query
            - queryRange
            - getTargets
```

---

## Usando Kubernetes Service como MCP Server

Puedes usar un Service de Kubernetes directamente como MCP server sin crear un RemoteMCPServer:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mi-mcp-service
  namespace: kagent
  # Label para descubrimiento automatico
  labels:
    kagent.dev/mcp-server: "true"
  # Anotaciones de configuracion
  annotations:
    kagent.dev/mcp-service-protocol: "streamable_http"  # o "sse"
    kagent.dev/mcp-service-path: "/mcp"
spec:
  ports:
    - name: mcp
      port: 8084
      targetPort: 8084
      protocol: TCP
      appProtocol: mcp
  selector:
    app: mi-mcp-app
---
# Usar en un Agent
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: mi-agente
spec:
  type: Declarative
  declarative:
    modelConfig: mi-modelo
    tools:
      - type: MCPServer
        mcpServer:
          name: mi-mcp-service
          kind: Service  # Usar Service directamente
```

### Anotaciones de Service

| Anotacion | Descripcion | Valores |
|-----------|-------------|---------|
| `kagent.dev/mcp-server` | Habilita descubrimiento | `"true"` |
| `kagent.dev/mcp-service-protocol` | Protocolo MCP | `"sse"`, `"streamable_http"` |
| `kagent.dev/mcp-service-path` | Path del endpoint | e.g., `"/mcp"` |

---

## Ejemplos Practicos

### 1. Agente Basico con OpenAI

```yaml
# Secret con API key
apiVersion: v1
kind: Secret
metadata:
  name: openai-secret
  namespace: kagent
type: Opaque
stringData:
  api-key: "sk-xxx..."
---
# Configuracion del modelo
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: gpt4-config
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4o
  apiKeySecret: openai-secret
  apiKeySecretKey: api-key
  openAI:
    temperature: "0.7"
    maxTokens: 2048
---
# Agente
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: asistente-basico
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Asistente de IA basico"
    systemMessage: "Eres un asistente util y amable."
    modelConfig: gpt4-config
    tools: []
```

### 2. Agente con Herramientas MCP

```yaml
# Servidor MCP remoto
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: kubernetes-mcp
  namespace: kagent
spec:
  url: "http://kubernetes-mcp.mcp-servers:8080/mcp"
  description: "Servidor MCP para Kubernetes"
  timeout: 30s
  sseReadTimeout: 5m0s
---
# Agente con tools
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-assistant
  namespace: kagent
spec:
  type: Declarative
  description: "Asistente para gestion de Kubernetes"
  declarative:
    systemMessage: |
      Eres un experto en Kubernetes.
      Usa las herramientas disponibles para ayudar al usuario.
    modelConfig: gpt4-config
    stream: true
    tools:
      - type: McpServer
        mcpServer:
          name: kubernetes-mcp
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - k8s_get_resources
            - k8s_describe_resource
            - k8s_get_logs
```

### 3. Agente con Anthropic Claude

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: anthropic-secret
  namespace: kagent
type: Opaque
stringData:
  api-key: "sk-ant-xxx..."
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: claude-config
  namespace: kagent
spec:
  provider: Anthropic
  model: claude-3-5-sonnet-20241022
  apiKeySecret: anthropic-secret
  apiKeySecretKey: api-key
  anthropic:
    temperature: "0.3"
    maxTokens: 4096
---
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: claude-assistant
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Asistente con Claude"
    systemMessage: "Eres Claude, un asistente de IA creado por Anthropic."
    modelConfig: claude-config
    tools: []
```

### 4. Agente con Ollama Local

```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: ollama-config
  namespace: kagent
spec:
  provider: Ollama
  model: llama3.2:latest
  ollama:
    host: "http://ollama.ai-tools:11434"
    options:
      temperature: "0.8"
      num_ctx: "4096"
---
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: local-assistant
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Asistente local con Ollama"
    systemMessage: "Eres un asistente ejecutandose localmente."
    modelConfig: ollama-config
    tools: []
```

### 5. Agente con TLS Personalizado

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: custom-ca
  namespace: kagent
type: Opaque
data:
  ca.crt: <certificado-base64>
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: internal-llm
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4
  apiKeySecret: openai-secret
  apiKeySecretKey: api-key
  openAI:
    baseUrl: "https://litellm-interno.empresa.com"
  tls:
    caCertSecretRef: custom-ca
    caCertSecretKey: ca.crt
```

### 6. Agente con Skills A2A

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: monitoring-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Agente de monitoreo empresarial"
    systemMessage: "Eres un experto en SRE y monitoreo."
    modelConfig: gpt4-config
    a2aConfig:
      skills:
        - id: query-prometheus
          name: Consultar Prometheus
          description: "Ejecuta consultas PromQL en Prometheus"
          tags:
            - monitoring
            - prometheus
            - metrics
          inputModes:
            - text
          outputModes:
            - text
          examples:
            - "Cual es el uso de CPU del namespace production?"
        - id: check-alerts
          name: Verificar Alertas
          description: "Verifica el estado de las alertas en Alertmanager"
          tags:
            - alerting
            - monitoring
          inputModes:
            - text
          outputModes:
            - text
    tools:
      - type: MCPServer
        mcpServer:
          name: prometheus-mcp
          kind: RemoteMCPServer
```

### 7. System Message desde ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-prompts
  namespace: kagent
data:
  k8s-expert: |
    Eres un experto administrador de Kubernetes.

    Reglas:
    - Siempre verifica antes de ejecutar comandos destructivos
    - Sigue las mejores practicas de seguridad
    - Explica tus acciones paso a paso
---
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-expert
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Experto en Kubernetes"
    systemMessageFrom:
      type: ConfigMap
      name: agent-prompts
      key: k8s-expert
    modelConfig: gpt4-config
    tools: []
```

### 8. Agentes Anidados (Agent como Tool)

```yaml
# Agente especialista
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: math-specialist
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Especialista en matematicas"
    systemMessage: "Eres un experto en matematicas. Resuelve problemas paso a paso."
    modelConfig: gpt4-config
    tools: []
---
# Agente coordinador que usa al especialista
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: coordinator
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Coordinador que delega a especialistas"
    systemMessage: "Delega tareas especializadas a los agentes correspondientes."
    modelConfig: gpt4-config
    tools:
      - type: Agent
        agent:
          name: math-specialist
```

### 9. Agente BYO (Bring Your Own)

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: custom-agent
  namespace: kagent
spec:
  type: BYO
  description: "Agente personalizado con deployment propio"
  byo:
    deployment:
      image: mi-registry.com/mi-agente:v2.0.0
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 4Gi
      env:
        - name: CUSTOM_CONFIG
          value: "production"
      nodeSelector:
        node-type: gpu
```

### 10. Agente con Memory (RAG)

```yaml
apiVersion: kagent.dev/v1alpha1
kind: Memory
metadata:
  name: docs-memory
  namespace: kagent
spec:
  provider: Pinecone
  apiKeySecretRef: pinecone-secret
  apiKeySecretKey: api-key
  pinecone:
    indexHost: "https://docs-index.svc.pinecone.io"
    topK: 5
    scoreThreshold: "0.75"
---
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: docs-assistant
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Asistente con memoria de documentacion"
    systemMessage: "Usa la documentacion disponible para responder preguntas."
    modelConfig: gpt4-config
    memory:
      - docs-memory
    tools: []
```

---

## Configuracion de Skills (Container Images)

### Que son los Skills?

Los **Skills** son paquetes de codigo y configuracion empaquetados como **imagenes de contenedor OCI** que se montan en el agente y le proporcionan capacidades especializadas. A diferencia de las herramientas MCP que exponen APIs, los Skills son **archivos ejecutables locales** que el agente puede usar directamente.

```
┌─────────────────────────────────────────────────────────────────┐
│                         AGENT POD                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────────────────────────────┐  │
│  │  Init        │    │           Main Container             │  │
│  │  Container   │    │                                      │  │
│  │              │    │  ┌────────────────────────────────┐  │  │
│  │  kagent-adk  │───▶│  │  /skills/                      │  │  │
│  │  pull-skills │    │  │  ├── data-analysis/            │  │  │
│  │              │    │  │  │   ├── SKILL.md              │  │  │
│  │  Descarga:   │    │  │  │   └── scripts/analyze.py    │  │  │
│  │  - skill1    │    │  │  └── pdf-processing/           │  │  │
│  │  - skill2    │    │  │      ├── SKILL.md              │  │  │
│  │              │    │  │      └── scripts/extract.py    │  │  │
│  └──────────────┘    │  └────────────────────────────────┘  │  │
│         │            │                  ▲                    │  │
│         │            │                  │                    │  │
│         ▼            │        Agent usa BashTool para       │  │
│  ┌──────────────┐    │        ejecutar scripts              │  │
│  │ emptyDir     │────┼──────────────────┘                   │  │
│  │ volume       │    │                                      │  │
│  │ /skills      │    └──────────────────────────────────────┘  │
│  └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
```

### Como Funcionan los Skills

1. **Init Container**: Antes de que el agente inicie, un init container ejecuta `kagent-adk pull-skills` que descarga las imagenes de skills especificadas
2. **Montaje**: Los skills se extraen y montan en `/skills` (volumen compartido read-only)
3. **Descubrimiento**: El agente usa `SkillsTool` para listar skills disponibles
4. **Carga**: El agente lee `SKILL.md` para obtener instrucciones
5. **Ejecucion**: El agente usa `BashTool` para ejecutar los scripts del skill

### Estructura de un Skill

Cada skill es una imagen OCI con la siguiente estructura:

```
skill-image/
├── SKILL.md           # Metadatos YAML + instrucciones (requerido)
├── LICENSE.txt        # Licencia del skill (opcional)
└── scripts/           # Scripts ejecutables
    ├── main.py
    ├── utils.py
    └── config.json
```

**Ejemplo de SKILL.md:**

```markdown
---
name: data-analysis
description: Analiza archivos CSV y Excel con pandas
license: Complete terms in LICENSE.txt
---

# Data Analysis Skill

Este skill te permite analizar datos de archivos CSV y Excel.

## Uso

1. Primero, stage el archivo del usuario:
   \`stage_artifacts(artifact_names=["archivo.csv"])\`

2. Ejecuta el analisis:
   \`bash("python /skills/data-analysis/scripts/analyze.py uploads/archivo.csv")\`

3. Retorna el resultado:
   \`return_artifacts(file_paths=["outputs/report.pdf"])\`
```

### Especificacion de Skills en Agent

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: mi-agente-con-skills
  namespace: kagent
spec:
  type: Declarative

  # Configuracion de Skills
  skills:
    # Lista de imagenes de skills a descargar (maximo 20)
    refs:
      - ghcr.io/mi-org/data-analysis-skill:v1.0.0
      - ghcr.io/mi-org/pdf-processing-skill:latest
      - mi-registry.com/custom-skill:v2.1.0

    # Solo para desarrollo/testing - NO usar en produccion
    insecureSkipVerify: false

  declarative:
    modelConfig: default-model-config
    systemMessage: |
      Tienes acceso a skills especializados.
      Usa el tool 'skills' para descubrir y cargar skills disponibles.
      Usa 'bash' para ejecutar los scripts de los skills.
    tools:
      # Los skills NO requieren tools MCP adicionales
      # El agente ya tiene acceso a SkillsTool y BashTool integrados
      []
```

### Opciones de Skills

| Campo | Tipo | Descripcion | Default |
|-------|------|-------------|---------|
| `refs` | []string | Lista de imagenes OCI de skills (max 20) | Requerido |
| `insecureSkipVerify` | bool | Permitir HTTP y skip TLS (solo dev) | `false` |

### Flujo de Ejecucion del Agente con Skills

```python
# Usuario: "Analiza mi archivo de ventas"

# 1. Agente descubre skills disponibles
agent: skills()
# → Lista: data-analysis, pdf-processing, etc.

# 2. Agente carga instrucciones del skill
agent: skills(command='data-analysis')
# → Retorna contenido de SKILL.md

# 3. Agente prepara archivo del usuario
agent: stage_artifacts(artifact_names=["ventas.csv"])
# → Archivo disponible en: uploads/ventas.csv

# 4. Agente ejecuta script del skill
agent: bash("cd /skills/data-analysis && python scripts/analyze.py ../../uploads/ventas.csv")
# → Script genera: outputs/analysis_report.pdf

# 5. Agente retorna resultado
agent: return_artifacts(file_paths=["outputs/analysis_report.pdf"])
# → Usuario puede descargar el reporte
```

### Directorio de Trabajo por Sesion

Cada sesion de agente tiene un directorio aislado:

```
/tmp/kagent/{session_id}/
├── skills/      → symlink a /skills (read-only, compartido)
├── uploads/     → archivos del usuario (writable)
├── outputs/     → archivos generados (writable)
└── *.py         → scripts temporales (writable)
```

### Ejemplo: Skill de Analisis de Datos

**1. Crear la imagen del skill:**

```dockerfile
FROM python:3.11-slim

# Instalar dependencias
RUN pip install pandas matplotlib seaborn

# Copiar skill
COPY SKILL.md /SKILL.md
COPY scripts/ /scripts/

# Label para identificar como skill
LABEL org.kagent.skill=true
```

**2. SKILL.md:**

```markdown
---
name: pandas-analysis
description: Analiza datos con pandas y genera visualizaciones
license: MIT
---

# Pandas Data Analysis

## Instrucciones

Para analizar un archivo CSV:

1. Stage el archivo: \`stage_artifacts(artifact_names=["data.csv"])\`
2. Ejecuta: \`bash("python /skills/pandas-analysis/scripts/analyze.py uploads/data.csv")\`
3. Retorna: \`return_artifacts(file_paths=["outputs/report.html"])\`
```

**3. Usar en Agent:**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: data-analyst
spec:
  type: Declarative
  skills:
    refs:
      - ghcr.io/mi-org/pandas-analysis:v1.0.0
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      Eres un analista de datos experto.
      Usa tus skills para analizar archivos del usuario.
```

### Skills vs Tools MCP

| Caracteristica | Skills | Tools MCP |
|----------------|--------|-----------|
| **Ubicacion** | Local en el pod del agente | Remoto via HTTP/SSE |
| **Empaquetado** | Imagen OCI | Servidor MCP |
| **Ejecucion** | `bash` + scripts locales | Llamadas HTTP |
| **Estado** | Stateless por sesion | Depende del servidor |
| **Uso de recursos** | Usa CPU/memoria del agente | Servidor independiente |
| **Casos de uso** | Procesamiento de archivos, scripts Python, analisis de datos | APIs externas, bases de datos, servicios cloud |

### Seguridad de Skills

- **Read-only**: El directorio `/skills` es de solo lectura
- **Aislamiento**: Cada sesion tiene su propio directorio de trabajo
- **Sandbox**: BashTool ejecuta en sandbox con timeouts
- **Limites**: Maximo 100MB por archivo, timeout 30s (120s para pip)

---

## Configuracion de Seguridad

kagent proporciona multiples capas de seguridad para proteger tu infraestructura y datos sensibles.

### 1. Security Context para Pods

Configura el contexto de seguridad en el Helm values:

```yaml
# values.yaml
podSecurityContext:
  fsGroup: 2000
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
```

### 2. Configuracion TLS para Proveedores LLM

ModelConfig soporta TLS personalizado para conectarse a proveedores LLM internos o con certificados personalizados:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: internal-llm-config
  namespace: kagent
spec:
  provider: OpenAI
  model: gpt-4o
  apiKeySecret: llm-api-key
  apiKeySecretKey: api-key

  # Configuracion TLS
  tls:
    # Referencia a Secret con certificado CA personalizado
    caCertSecretRef: internal-ca-cert
    caCertSecretKey: ca.crt

    # SOLO para desarrollo - NO usar en produccion
    # disableVerify: false

    # Deshabilitar CAs del sistema (usar solo CA personalizado)
    # disableSystemCAs: false
```

**Crear el Secret con el certificado CA:**

```bash
kubectl create secret generic internal-ca-cert \
  --namespace kagent \
  --from-file=ca.crt=/path/to/ca-certificate.pem
```

### 3. RBAC - Control de Acceso Basado en Roles

kagent crea ClusterRoles para controlar el acceso a recursos:

#### ClusterRole: Getter (Solo lectura)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kagent-getter-role
rules:
- apiGroups: ["kagent.dev"]
  resources:
  - agents
  - modelconfigs
  - remotemcpservers
  - memories
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
```

#### ClusterRole: Writer (Lectura/Escritura)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kagent-writer-role
rules:
- apiGroups: ["kagent.dev"]
  resources:
  - agents
  - modelconfigs
  - remotemcpservers
  - memories
  verbs: ["create", "update", "patch", "delete"]
```

#### Crear RoleBinding para Usuarios

```yaml
# Solo lectura para equipo de observabilidad
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kagent-observability-team
  namespace: kagent
subjects:
- kind: Group
  name: observability-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagent-getter-role
  apiGroup: rbac.authorization.k8s.io
---
# Lectura/escritura para equipo de plataforma
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kagent-platform-team
  namespace: kagent
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kagent-writer-role
  apiGroup: rbac.authorization.k8s.io
```

### 4. Gestion Segura de Secrets

#### Uso con External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kagent-openai
  namespace: kagent
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: kagent-openai
    creationPolicy: Owner
  data:
  - secretKey: OPENAI_API_KEY
    remoteRef:
      key: secret/data/kagent/openai
      property: api_key
```

#### Uso con Sealed Secrets

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: kagent-openai
  namespace: kagent
spec:
  encryptedData:
    OPENAI_API_KEY: AgBy8hT...encrypted...
  template:
    metadata:
      name: kagent-openai
      namespace: kagent
```

### 5. Network Policies

Restringe el trafico de red entre componentes:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kagent-controller-policy
  namespace: kagent
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: controller
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Permitir trafico desde UI
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: ui
    ports:
    - protocol: TCP
      port: 8083
  egress:
  # Permitir trafico a API de Kubernetes
  - to: []
    ports:
    - protocol: TCP
      port: 443
  # Permitir trafico a agentes
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/part-of: kagent
    ports:
    - protocol: TCP
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kagent-agent-policy
  namespace: kagent
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: kagent
  policyTypes:
  - Egress
  egress:
  # Permitir trafico a proveedores LLM externos
  - to: []
    ports:
    - protocol: TCP
      port: 443
  # Permitir trafico a MCP servers
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          kagent.dev/mcp-server: "true"
    ports:
    - protocol: TCP
      port: 3000
```

### 6. ServiceAccount por Agente

Cada agente puede tener su propio ServiceAccount con permisos limitados:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-reader-agent
  namespace: kagent
spec:
  type: Declarative
  # ServiceAccount personalizado para el agente
  serviceAccountName: k8s-reader-sa
  declarative:
    modelConfig: default-model-config
    systemMessage: "Solo puedes leer recursos de Kubernetes"
    tools:
      - type: McpServer
        mcpServer:
          name: k8s-tools
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - get_pod
            - list_pods
            - get_deployment
            # NO incluir: create, delete, patch
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-reader-sa
  namespace: kagent
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: k8s-reader-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: k8s-reader-sa
  namespace: kagent
roleRef:
  kind: ClusterRole
  name: view  # Solo permisos de lectura
  apiGroup: rbac.authorization.k8s.io
```

### 7. Integracion con Cloud IAM

#### AWS IRSA (IAM Roles for Service Accounts)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-agent-sa
  namespace: kagent
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/kagent-s3-role"
    eks.amazonaws.com/sts-regional-endpoints: "true"
```

#### GCP Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gcp-agent-sa
  namespace: kagent
  annotations:
    iam.gke.io/gcp-service-account: "kagent-sa@mi-proyecto.iam.gserviceaccount.com"
```

#### Azure Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: azure-agent-sa
  namespace: kagent
  annotations:
    azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"
  labels:
    azure.workload.identity/use: "true"
```

### 8. Restriccion de Namespaces

Limita los namespaces que el controller puede observar:

```yaml
# values.yaml
controller:
  # Solo observar namespaces especificos
  watchNamespaces:
    - kagent
    - agents-prod
    - agents-staging
  # Si esta vacio, observa TODOS los namespaces
```

### 9. Pod Security Standards

Aplica estandares de seguridad a nivel de namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kagent
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 10. Audit Logging

kagent genera logs de auditoria para todas las operaciones:

```yaml
# values.yaml
controller:
  loglevel: "info"  # debug, info, warn, error

otel:
  tracing:
    enabled: true
    exporter:
      otlp:
        endpoint: http://otel-collector:4317
  logging:
    enabled: true
    exporter:
      otlp:
        endpoint: http://otel-collector:4317
```

### Resumen de Caracteristicas de Seguridad

| Caracteristica | Estado | Descripcion |
|----------------|--------|-------------|
| **TLS/mTLS** | ✅ Soportado | CA personalizado para proveedores LLM |
| **RBAC** | ✅ Soportado | ClusterRoles getter/writer |
| **Network Policies** | ✅ Soportado | Restriccion de trafico |
| **Pod Security** | ✅ Soportado | SecurityContext, PSS |
| **Secret Management** | ✅ Soportado | Secrets, ESO, Sealed Secrets |
| **Cloud IAM** | ✅ Soportado | IRSA, Workload Identity |
| **Multi-tenancy** | 🔄 En desarrollo | Issue #476 |
| **Audit Logging** | ✅ Soportado | OpenTelemetry |
| **Session Isolation** | 🔄 En desarrollo | Issue #476 |
| **Signed Images** | 🔄 Planificado | Cosign keyless |
| **SBOM** | 🔄 Planificado | Software Bill of Materials |

### Referencias de Seguridad

- [SECURITY.md](https://github.com/kagent-dev/kagent/blob/main/SECURITY.md) - Politica de seguridad
- [Security Self-Assessment](https://github.com/kagent-dev/kagent/blob/main/contrib/cncf/security-self-assessment.md) - Evaluacion CNCF
- [OpenSSF Best Practices](https://www.bestpractices.dev/projects/10723) - Certificacion OpenSSF

---

## Referencia Rapida

### Tipos de MCP Server

| Kind | API Group | Descripcion | Ejemplo de uso en Agent |
|------|-----------|-------------|-------------------------|
| `RemoteMCPServer` | `kagent.dev` | CRD de kagent para MCP HTTP/SSE remoto | `kind: RemoteMCPServer, apiGroup: kagent.dev` |
| `Service` | - | Service de K8s con anotaciones MCP | `kind: Service` |
| `MCPServer` | `kmcp.dev` | Recurso de kmcp para stdio | `kind: MCPServer` |

### Sintaxis de Tools en Agent

```yaml
# Usando RemoteMCPServer
tools:
  - type: McpServer
    mcpServer:
      name: mi-mcp-server
      kind: RemoteMCPServer
      apiGroup: kagent.dev
      toolNames:
        - tool1
        - tool2

# Usando Service de Kubernetes
tools:
  - type: McpServer
    mcpServer:
      name: mi-servicio-mcp
      kind: Service
```

### Condiciones de Status

| Condicion | Descripcion |
|-----------|-------------|
| `Ready` | El agente esta listo para recibir requests |
| `Accepted` | La configuracion ha sido validada |

### Protocolos MCP Soportados

| Protocolo | Descripcion | Default |
|-----------|-------------|---------|
| `SSE` | Server-Sent Events (legacy) | No |
| `STREAMABLE_HTTP` | HTTP con streaming | Si |

### Limites

- Maximo 20 tools por agente
- Maximo 500 paginas en diseños
