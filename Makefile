# K2A Enterprise Monitoring Makefile
# Inspired by kagent project patterns

# Image URL to use all building/pushing image targets
IMG_REGISTRY ?= quay.io/k2a-enterprise
IMG_NAME ?= k2a-monitoring
IMG_TAG ?= latest
IMG ?= $(IMG_REGISTRY)/$(IMG_NAME):$(IMG_TAG)

# Kubernetes and Helm configuration
NAMESPACE ?= k2a-monitoring
CLUSTER_NAME ?= local-cluster
HELM_RELEASE ?= k2a-monitoring

# Build configuration
GOVERSION := 1.21
GOOS := linux
GOARCH := amd64
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_COMMIT := $(shell git rev-parse HEAD)
GIT_TAG := $(shell git describe --tags --always)
VERSION ?= $(GIT_TAG)

# Build flags
LDFLAGS := -X main.version=$(VERSION) \
           -X main.gitCommit=$(GIT_COMMIT) \
           -X main.buildDate=$(BUILD_DATE)

# Tool dependencies
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
KUSTOMIZE ?= $(LOCALBIN)/kustomize
ENVTEST ?= $(LOCALBIN)/setup-envtest
HELM ?= helm
KIND ?= kind

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

# CONTAINER_TOOL defines the container tool to be used for building images.
CONTAINER_TOOL ?= docker

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

.PHONY: lint
lint: ## Run golangci-lint against code.
	golangci-lint run

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags="$(LDFLAGS)" -o bin/manager cmd/controller/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/controller/main.go

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build --platform linux/$(GOARCH) -t $(IMG) \
		--build-arg VERSION=$(VERSION) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		.

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push $(IMG)

.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for cross-platform support
	$(CONTAINER_TOOL) buildx create --name project-v3-builder || true
	$(CONTAINER_TOOL) buildx use project-v3-builder
	$(CONTAINER_TOOL) buildx build --push --platform linux/arm64,linux/amd64 -t $(IMG) \
		--build-arg VERSION=$(VERSION) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		.

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install-crds
install-crds: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | oc apply -f -

.PHONY: uninstall-crds
uninstall-crds: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | oc delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy-dev
deploy-dev: docker-build ## Deploy to development environment
	./scripts/deploy.sh dev deploy

.PHONY: deploy-staging
deploy-staging: docker-build ## Deploy to staging environment
	./scripts/deploy.sh staging deploy

.PHONY: deploy-prod
deploy-prod: docker-push ## Deploy to production environment
	./scripts/deploy.sh prod deploy

.PHONY: undeploy
undeploy: ## Undeploy from K8s cluster specified in ~/.kube/config.
	./scripts/deploy.sh $(ENV) cleanup

##@ Helm

.PHONY: helm-dependency-update
helm-dependency-update: ## Update helm dependencies
	$(HELM) dependency update helm/k2a-monitoring

.PHONY: helm-lint
helm-lint: ## Lint helm chart
	$(HELM) lint helm/k2a-monitoring

.PHONY: helm-template
helm-template: ## Template helm chart
	$(HELM) template $(HELM_RELEASE) helm/k2a-monitoring \
		--namespace $(NAMESPACE) \
		--set image.repository=$(IMG_REGISTRY)/$(IMG_NAME) \
		--set image.tag=$(IMG_TAG)

.PHONY: helm-install
helm-install: helm-dependency-update ## Install helm chart
	$(HELM) upgrade --install $(HELM_RELEASE) helm/k2a-monitoring \
		--namespace $(NAMESPACE) --create-namespace \
		--set image.repository=$(IMG_REGISTRY)/$(IMG_NAME) \
		--set image.tag=$(IMG_TAG) \
		--wait --timeout 300s

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall helm chart
	$(HELM) uninstall $(HELM_RELEASE) --namespace $(NAMESPACE)

##@ Testing

.PHONY: test-unit
test-unit: ## Run unit tests
	go test -v -race -coverprofile=coverage.out ./internal/... ./pkg/...

.PHONY: test-integration
test-integration: envtest ## Run integration tests
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" \
	go test -v -tags=integration ./test/integration/...

.PHONY: test-e2e
test-e2e: ## Run e2e tests
	go test -v -tags=e2e ./test/e2e/...

.PHONY: test-all
test-all: test-unit test-integration ## Run all tests

##@ Security

.PHONY: security-scan
security-scan: ## Run security scans
	@echo "Running Trivy security scan..."
	trivy fs --security-checks vuln,config .
	@echo "Running Gosec security scan..."
	gosec ./...

.PHONY: security-scan-image
security-scan-image: ## Scan docker image for vulnerabilities
	trivy image $(IMG)

##@ Kind Cluster

.PHONY: check-dependencies
check-dependencies: ## Check required dependencies
	@echo "Checking dependencies..."
	@command -v kind >/dev/null 2>&1 || (echo "❌ kind not found" && exit 1)
	@command -v kubectl >/dev/null 2>&1 || (echo "❌ kubectl not found" && exit 1)
	@command -v helm >/dev/null 2>&1 || (echo "❌ helm not found" && exit 1)
	@command -v docker >/dev/null 2>&1 || (echo "❌ docker not found" && exit 1)
	@echo "✅ All dependencies found"

.PHONY: kind-create
kind-create: check-dependencies ## Create kind cluster with local registry
	./scripts/kind/setup-kind.sh

.PHONY: kind-delete
kind-delete: ## Delete kind cluster and registry
	$(KIND) delete cluster --name k2a-monitoring
	docker rm -f k2a-registry || true

.PHONY: kind-load
kind-load: docker-build ## Load docker image into kind cluster
	$(KIND) load docker-image $(IMG) --name k2a-monitoring

.PHONY: kind-deploy
kind-deploy: kind-create kind-load helm-install ## Full deployment to kind cluster

.PHONY: kind-test
kind-test: kind-deploy ## Run tests against kind cluster
	./scripts/test.sh dev all

.PHONY: kind-status
kind-status: ## Show kind cluster status
	@echo "=== Kind Cluster Status ==="
	$(KIND) get clusters
	kubectl get nodes -o wide
	@echo "\n=== K2A Monitoring Status ==="
	kubectl get pods -n k2a-monitoring
	kubectl get svc -n k2a-monitoring

##@ Monitoring Setup

.PHONY: monitoring-setup
monitoring-setup: ## Setup monitoring stack
	./scripts/monitoring-setup.sh $(ENV) all

.PHONY: monitoring-verify
monitoring-verify: ## Verify monitoring setup
	./scripts/monitoring-setup.sh $(ENV) verify

.PHONY: monitoring-info
monitoring-info: ## Show monitoring access info
	./scripts/monitoring-setup.sh $(ENV) info

##@ Quality

.PHONY: quality
quality: fmt vet lint test-unit security-scan ## Run all quality checks

.PHONY: ci
ci: quality test-integration docker-build security-scan-image ## Run CI pipeline

##@ Tool Dependencies

CONTROLLER_TOOLS_VERSION ?= v0.13.0
KUSTOMIZE_VERSION ?= v5.0.4-0.20230601165947-6ce0bf390ce3
ENVTEST_K8S_VERSION = 1.28.3

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	test -s $(LOCALBIN)/kustomize || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

##@ Clean

.PHONY: clean
clean: ## Clean build artifacts
	rm -rf bin/ cover.out $(LOCALBIN)
	$(CONTAINER_TOOL) system prune -f

.PHONY: clean-all
clean-all: clean kind-delete helm-uninstall ## Clean everything