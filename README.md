# K2A Enterprise Monitoring para OpenShift

## Estructura del Proyecto

```
k2a-enterprise-monitoring/
├── manifests/
│   ├── base/                   # Manifiestos base de Kubernetes
│   │   ├── rbac/              # Roles, RoleBindings, ServiceAccounts
│   │   ├── monitoring/        # ServiceMonitor, PrometheusRule
│   │   ├── security/          # SecurityContextConstraints, NetworkPolicies
│   │   ├── configmaps/        # Configuraciones de la aplicación
│   │   ├── deployments/       # Deployments del kagent
│   │   └── services/          # Services y endpoints
│   └── overlays/              # Overlays para diferentes entornos
│       ├── dev/
│       ├── staging/
│       └── prod/
├── configs/                   # Configuraciones específicas del kagent
├── scripts/                   # Scripts de deployment y mantenimiento
├── docs/                      # Documentación técnica
└── charts/                    # Helm charts (opcional)
```

## Componentes

- **K2A Agent**: Agente principal para monitoreo del clúster
- **Monitoring Stack**: Integración con Prometheus/Grafana
- **Security**: Configuraciones de seguridad para OpenShift
- **Multi-environment**: Soporte para dev/staging/prod