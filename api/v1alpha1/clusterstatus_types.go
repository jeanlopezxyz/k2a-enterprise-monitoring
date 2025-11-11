/*
Copyright 2024 K2A Enterprise Monitoring.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ClusterMonitorSpec defines the desired state of ClusterMonitor
type ClusterMonitorSpec struct {
	// Interval for cluster monitoring collection
	// +kubebuilder:validation:Pattern="^[0-9]+(s|m|h)$"
	// +kubebuilder:default="30s"
	Interval string `json:"interval,omitempty"`

	// Metrics collection configuration
	// +kubebuilder:validation:Required
	MetricsCollection MetricsCollectionSpec `json:"metricsCollection"`

	// Alert thresholds configuration
	// +optional
	AlertThresholds *AlertThresholdsSpec `json:"alertThresholds,omitempty"`

	// Export configuration
	// +optional
	Export *ExportSpec `json:"export,omitempty"`

	// Target cluster configuration
	// +optional
	TargetCluster *TargetClusterSpec `json:"targetCluster,omitempty"`
}

// MetricsCollectionSpec defines what metrics to collect
type MetricsCollectionSpec struct {
	// Enable node metrics collection
	// +kubebuilder:default=true
	Nodes bool `json:"nodes,omitempty"`

	// Enable pod metrics collection
	// +kubebuilder:default=true
	Pods bool `json:"pods,omitempty"`

	// Enable service metrics collection
	// +kubebuilder:default=true
	Services bool `json:"services,omitempty"`

	// Enable persistent volume metrics collection
	// +kubebuilder:default=false
	PersistentVolumes bool `json:"persistentVolumes,omitempty"`

	// Namespaces to monitor (empty = all)
	// +optional
	Namespaces []string `json:"namespaces,omitempty"`

	// Custom metrics configuration
	// +optional
	CustomMetrics []CustomMetricSpec `json:"customMetrics,omitempty"`
}

// CustomMetricSpec defines a custom metric to collect
type CustomMetricSpec struct {
	// Name of the custom metric
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern="^[a-zA-Z_][a-zA-Z0-9_]*$"
	Name string `json:"name"`

	// Query to execute for this metric
	// +kubebuilder:validation:Required
	Query string `json:"query"`

	// Interval for this specific metric
	// +kubebuilder:validation:Pattern="^[0-9]+(s|m|h)$"
	// +optional
	Interval *string `json:"interval,omitempty"`
}

// AlertThresholdsSpec defines alert thresholds
type AlertThresholdsSpec struct {
	// CPU usage threshold (percentage)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=100
	// +kubebuilder:default=80
	CPUThreshold int `json:"cpuThreshold,omitempty"`

	// Memory usage threshold (percentage)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=100
	// +kubebuilder:default=85
	MemoryThreshold int `json:"memoryThreshold,omitempty"`

	// Disk usage threshold (percentage)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=100
	// +kubebuilder:default=90
	DiskThreshold int `json:"diskThreshold,omitempty"`

	// Pod restart count threshold
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:default=5
	PodRestartThreshold int `json:"podRestartThreshold,omitempty"`
}

// ExportSpec defines export configuration
type ExportSpec struct {
	// Export formats to enable
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:Enum=prometheus;json;csv
	Formats []string `json:"formats"`

	// S3 configuration for exports
	// +optional
	S3Config *S3ConfigSpec `json:"s3Config,omitempty"`

	// Export schedule
	// +kubebuilder:validation:Pattern="^(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|(@every [0-9]+(s|m|h))|([0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+)$"
	// +optional
	Schedule *string `json:"schedule,omitempty"`
}

// S3ConfigSpec defines S3 export configuration
type S3ConfigSpec struct {
	// S3 bucket name
	// +kubebuilder:validation:Required
	Bucket string `json:"bucket"`

	// S3 region
	// +kubebuilder:validation:Required
	Region string `json:"region"`

	// S3 endpoint (for compatible services)
	// +optional
	Endpoint *string `json:"endpoint,omitempty"`

	// Credentials secret reference
	// +kubebuilder:validation:Required
	CredentialsSecretRef SecretRef `json:"credentialsSecretRef"`
}

// SecretRef references a secret
type SecretRef struct {
	// Secret name
	// +kubebuilder:validation:Required
	Name string `json:"name"`

	// Secret key for access key ID
	// +kubebuilder:default="access-key-id"
	AccessKeyIDKey string `json:"accessKeyIDKey,omitempty"`

	// Secret key for secret access key
	// +kubebuilder:default="secret-access-key"
	SecretAccessKeyKey string `json:"secretAccessKeyKey,omitempty"`
}

// TargetClusterSpec defines remote cluster monitoring
type TargetClusterSpec struct {
	// Cluster name
	// +kubebuilder:validation:Required
	Name string `json:"name"`

	// Kubeconfig secret reference
	// +kubebuilder:validation:Required
	KubeconfigSecretRef SecretRef `json:"kubeconfigSecretRef"`

	// Server endpoint
	// +optional
	Endpoint *string `json:"endpoint,omitempty"`
}

// ClusterMonitorStatus defines the observed state of ClusterMonitor
type ClusterMonitorStatus struct {
	// Current phase of the monitor
	// +kubebuilder:validation:Enum=Pending;Running;Error;Stopping
	Phase string `json:"phase,omitempty"`

	// Last successful collection timestamp
	// +optional
	LastCollection *metav1.Time `json:"lastCollection,omitempty"`

	// Number of metrics collected in last run
	// +optional
	MetricsCollected *int32 `json:"metricsCollected,omitempty"`

	// Current conditions
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// Observer health status
	// +optional
	Health *HealthStatus `json:"health,omitempty"`

	// Export status
	// +optional
	ExportStatus *ExportStatus `json:"exportStatus,omitempty"`
}

// HealthStatus defines health information
type HealthStatus struct {
	// Overall health status
	// +kubebuilder:validation:Enum=Healthy;Warning;Critical;Unknown
	Status string `json:"status"`

	// Last health check
	// +optional
	LastCheck *metav1.Time `json:"lastCheck,omitempty"`

	// Health details
	// +optional
	Details string `json:"details,omitempty"`
}

// ExportStatus defines export status
type ExportStatus struct {
	// Last export timestamp
	// +optional
	LastExport *metav1.Time `json:"lastExport,omitempty"`

	// Export error if any
	// +optional
	Error *string `json:"error,omitempty"`

	// Number of records exported
	// +optional
	RecordsExported *int64 `json:"recordsExported,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:resource:scope=Namespaced,shortName=cm
//+kubebuilder:printcolumn:name="Phase",type="string",JSONPath=".status.phase"
//+kubebuilder:printcolumn:name="Health",type="string",JSONPath=".status.health.status"
//+kubebuilder:printcolumn:name="Last Collection",type="date",JSONPath=".status.lastCollection"
//+kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// ClusterMonitor is the Schema for the clustermonitors API
type ClusterMonitor struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ClusterMonitorSpec   `json:"spec,omitempty"`
	Status ClusterMonitorStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// ClusterMonitorList contains a list of ClusterMonitor
type ClusterMonitorList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ClusterMonitor `json:"items"`
}