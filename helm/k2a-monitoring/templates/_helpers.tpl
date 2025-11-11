{{/*
K2A Enterprise Monitoring Helm Templates
Inspired by kagent project patterns
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "k2a-monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "k2a-monitoring.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "k2a-monitoring.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k2a-monitoring.labels" -}}
helm.sh/chart: {{ include "k2a-monitoring.chart" . }}
{{ include "k2a-monitoring.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k2a-monitoring.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k2a-monitoring.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Controller labels
*/}}
{{- define "k2a-monitoring.controller.labels" -}}
{{ include "k2a-monitoring.labels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Controller selector labels
*/}}
{{- define "k2a-monitoring.controller.selectorLabels" -}}
{{ include "k2a-monitoring.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Agent labels
*/}}
{{- define "k2a-monitoring.agent.labels" -}}
{{ include "k2a-monitoring.labels" . }}
app.kubernetes.io/component: agent
{{- end }}

{{/*
Agent selector labels
*/}}
{{- define "k2a-monitoring.agent.selectorLabels" -}}
{{ include "k2a-monitoring.selectorLabels" . }}
app.kubernetes.io/component: agent
{{- end }}

{{/*
Create the name of the service account to use for the controller
*/}}
{{- define "k2a-monitoring.controller.serviceAccountName" -}}
{{- if .Values.rbac.serviceAccount.create }}
{{- default (printf "%s-controller" (include "k2a-monitoring.fullname" .)) .Values.rbac.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use for the agent
*/}}
{{- define "k2a-monitoring.agent.serviceAccountName" -}}
{{- if .Values.rbac.serviceAccount.create }}
{{- default (printf "%s-agent" (include "k2a-monitoring.fullname" .)) .Values.rbac.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the cluster role
*/}}
{{- define "k2a-monitoring.clusterRoleName" -}}
{{- if .Values.rbac.clusterRole.name }}
{{- .Values.rbac.clusterRole.name }}
{{- else }}
{{- printf "%s-reader" (include "k2a-monitoring.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Create the name of the SCC
*/}}
{{- define "k2a-monitoring.sccName" -}}
{{- if .Values.scc.name }}
{{- .Values.scc.name }}
{{- else }}
{{- printf "%s-scc" (include "k2a-monitoring.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Controller image name
*/}}
{{- define "k2a-monitoring.controller.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.controller.image.repository }}
{{- $tag := .Values.controller.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Agent image name
*/}}
{{- define "k2a-monitoring.agent.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.agent.image.repository }}
{{- $tag := .Values.agent.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Image pull policy
*/}}
{{- define "k2a-monitoring.imagePullPolicy" -}}
{{- .Values.global.imagePullPolicy | default "IfNotPresent" }}
{{- end }}

{{/*
Image pull secrets
*/}}
{{- define "k2a-monitoring.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Security context for containers
*/}}
{{- define "k2a-monitoring.securityContext" -}}
{{- if .component.securityContext }}
securityContext:
  {{- toYaml .component.securityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Pod security context
*/}}
{{- define "k2a-monitoring.podSecurityContext" -}}
{{- if .component.podSecurityContext }}
securityContext:
  {{- toYaml .component.podSecurityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Resources configuration
*/}}
{{- define "k2a-monitoring.resources" -}}
{{- if .component.resources }}
resources:
  {{- toYaml .component.resources | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Affinity configuration
*/}}
{{- define "k2a-monitoring.affinity" -}}
{{- if .component.affinity }}
affinity:
  {{- toYaml .component.affinity | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Tolerations configuration
*/}}
{{- define "k2a-monitoring.tolerations" -}}
{{- if .component.tolerations }}
tolerations:
  {{- toYaml .component.tolerations | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Environment-specific values
*/}}
{{- define "k2a-monitoring.environmentValues" -}}
{{- $environment := .Values.global.environment | default "prod" }}
{{- if hasKey .Values.environments $environment }}
{{- get .Values.environments $environment | toYaml }}
{{- end }}
{{- end }}

{{/*
Merge environment-specific controller values
*/}}
{{- define "k2a-monitoring.controller.finalValues" -}}
{{- $global := .Values.controller }}
{{- $environment := .Values.global.environment | default "prod" }}
{{- if hasKey .Values.environments $environment }}
{{- $envValues := get .Values.environments $environment }}
{{- if hasKey $envValues "controller" }}
{{- $global = mergeOverwrite $global $envValues.controller }}
{{- end }}
{{- end }}
{{- $global | toYaml }}
{{- end }}

{{/*
Merge environment-specific agent values
*/}}
{{- define "k2a-monitoring.agent.finalValues" -}}
{{- $global := .Values.agent }}
{{- $environment := .Values.global.environment | default "prod" }}
{{- if hasKey .Values.environments $environment }}
{{- $envValues := get .Values.environments $environment }}
{{- if hasKey $envValues "agent" }}
{{- $global = mergeOverwrite $global $envValues.agent }}
{{- end }}
{{- end }}
{{- $global | toYaml }}
{{- end }}

{{/*
OpenShift route host
*/}}
{{- define "k2a-monitoring.route.host" -}}
{{- if .Values.route.host }}
{{- .Values.route.host }}
{{- else }}
{{- printf "%s-%s.%s" (include "k2a-monitoring.fullname" .) .Release.Namespace (.Values.route.domain | default "apps.cluster.local") }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "k2a-monitoring.annotations" -}}
{{- if .Values.global.commonAnnotations }}
{{ toYaml .Values.global.commonAnnotations }}
{{- end }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "k2a-monitoring.configMapName" -}}
{{- printf "%s-config" (include "k2a-monitoring.fullname" .) }}
{{- end }}

{{/*
ServiceMonitor namespace
*/}}
{{- define "k2a-monitoring.serviceMonitor.namespace" -}}
{{- if .Values.monitoring.serviceMonitor.namespace }}
{{- .Values.monitoring.serviceMonitor.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
PrometheusRule namespace
*/}}
{{- define "k2a-monitoring.prometheusRule.namespace" -}}
{{- if .Values.monitoring.prometheusRule.namespace }}
{{- .Values.monitoring.prometheusRule.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Validate required values
*/}}
{{- define "k2a-monitoring.validateValues" -}}
{{- if not .Values.controller.image.repository }}
{{- fail "controller.image.repository is required" }}
{{- end }}
{{- if not .Values.agent.image.repository }}
{{- fail "agent.image.repository is required" }}
{{- end }}
{{- if and .Values.global.openshift.enabled (not .Values.scc.enabled) }}
{{- fail "SCC must be enabled when OpenShift support is enabled" }}
{{- end }}
{{- end }}