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
9. [Usando Kubernetes Service como MCP Server](#usando-kubernetes-service-como-mcp-server)
10. [Configuracion de ToolServer (DEPRECADO)](#configuracion-de-toolserver-deprecado)
11. [Ejemplos Practicos](#ejemplos-practicos)

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

#### 1. Agregar el Repositorio

```bash
helm repo add kagent https://kagent-dev.github.io/kagent
helm repo update
```

#### 2. Crear el Namespace

```bash
kubectl create namespace kagent-system
```

#### 3. Crear el Secret con API Key

```bash
kubectl create secret generic kagent-openai \
  --namespace kagent-system \
  --from-literal=api-key="${OPENAI_API_KEY}"
```

#### 4. Instalar con Helm

```bash
# Instalacion basica
helm install kagent kagent/kagent \
  --namespace kagent-system \
  --set modelConfig.apiKeySecret=kagent-openai

# Instalacion con valores personalizados
helm install kagent kagent/kagent \
  --namespace kagent-system \
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
    repoURL: https://kagent-dev.github.io/kagent
    chart: kagent
    targetRevision: 0.1.0  # Especificar version
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
        repoURL: https://kagent-dev.github.io/kagent
        chart: kagent
        targetRevision: 0.1.0
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
    - https://kagent-dev.github.io/kagent
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

| Tipo | Descripcion |
|------|-------------|
| `Declarative` | Gestionado por kagent, deployment automatico |
| `BYO` (Bring Your Own) | El usuario proporciona su propio deployment |

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
      # Tipo 1: MCP Server
      - type: MCPServer
        mcpServer:
          name: mi-mcp-server
          kind: RemoteMCPServer  # RemoteMCPServer, Service, o MCPServer (kmcp)
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

      # Tipo 2: Otro Agent como herramienta (agentes anidados)
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
| `type` | string | `MCPServer` o `Agent` |
| `mcpServer.name` | string | Nombre del recurso MCP |
| `mcpServer.kind` | string | `RemoteMCPServer`, `Service`, `MCPServer` |
| `mcpServer.toolNames` | []string | Tools especificos a exponer (opcional) |
| `agent.name` | string | Nombre del Agent a usar como tool |
| `headersFrom` | []ValueRef | Headers de autenticacion |

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
  protocol: STREAMABLE_HTTP
---
# Agente con tools
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-assistant
  namespace: kagent
spec:
  type: Declarative
  declarative:
    description: "Asistente para gestion de Kubernetes"
    systemMessage: |
      Eres un experto en Kubernetes.
      Usa las herramientas disponibles para ayudar al usuario.
    modelConfig: gpt4-config
    tools:
      - type: MCPServer
        mcpServer:
          name: kubernetes-mcp
          kind: RemoteMCPServer
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

## Referencia Rapida

### Tipos de MCP Server

| Kind | Descripcion |
|------|-------------|
| `RemoteMCPServer` | CRD de kagent para MCP remoto |
| `Service` | Service de K8s con anotaciones MCP |
| `MCPServer` | Recurso de kmcp |

### Condiciones de Status

| Condicion | Descripcion |
|-----------|-------------|
| `Ready` | El agente esta listo para recibir requests |
| `Accepted` | La configuracion ha sido validada |

### Limites

- Maximo 20 tools por agente
- Maximo 500 paginas en diseños
