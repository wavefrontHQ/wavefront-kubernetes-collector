PREFIX?=wavefronthq
GCP_PROJECT=wavefront-gcp-dev
DOCKER_IMAGE?=wavefront-kubernetes-collector
ARCH?=amd64

REPO_DIR=$(shell git rev-parse --show-toplevel)
KUSTOMIZE_DIR=$(REPO_DIR)/hack/kustomize
DEPLOY_DIR=$(REPO_DIR)/hack/deploy
OUT_DIR?=$(REPO_DIR)/_output

GOLANG_VERSION?=1.15
BINARY_NAME=wavefront-collector

RELEASE_TYPE?=release
RC_NUMBER?=1
GIT_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
GIT_HUB_REPO=wavefrontHQ/wavefront-collector-for-kubernetes

ECR_REPO_PREFIX=tobs/k8s/saas
WAVEFRONT_DEV_AWS_ACC_ID=095415062695
AWS_PROFILE=wavefront-dev
AWS_REGION=us-west-2
ECR_ENDPOINT=${WAVEFRONT_DEV_AWS_ACC_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

K8S_ENV=$(shell cd $(DEPLOY_DIR) && ./get-k8s-cluster-env.sh)

ifndef TEMP_DIR
TEMP_DIR:=$(shell mktemp -d /tmp/wavefront.XXXXXX)
endif

VERSION?=1.5.1
GIT_COMMIT:=$(shell git rev-parse --short HEAD)

# for testing, the built image will also be tagged with this name provided via an environment variable
OVERRIDE_IMAGE_NAME?=${COLLECTOR_TEST_IMAGE}

LDFLAGS=-w -X main.version=$(VERSION) -X main.commit=$(GIT_COMMIT)

all: container

fmt:
	find . -type f -name "*.go" | grep -v "./vendor*" | xargs gofmt -s -w

tests:
	go clean -testcache
	go test -timeout 30s -race ./...

build: clean fmt vet
	GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(OUT_DIR)/$(ARCH)/$(BINARY_NAME) ./cmd/wavefront-collector/

vet:
	go vet -composites=false ./...

# test driver for local development
driver: clean fmt
	GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(OUT_DIR)/$(ARCH)/$(BINARY_NAME)-test ./cmd/test-driver/

containers: container test-proxy-container

container:
	@BINARY_NAME=$(BINARY_NAME) LDFLAGS="$(LDFLAGS)" PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) OVERRIDE_IMAGE_NAME=$(OVERRIDE_IMAGE_NAME) ./hack/make/container.sh

github-release:
	@GITHUB_TOKEN=$(GITHUB_TOKEN) VERSION=$(VERSION) GIT_BRANCH=$(GIT_BRANCH) GIT_HUB_REPO=$(GIT_HUB_REPO) ./hack/make/github-release.sh

release:
	@BINARY_NAME=$(BINARY_NAME) LDFLAGS="$(LDFLAGS)" PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) RC_NUMBER=$(RC_NUMBER) ./hack/make/release.sh

test-proxy-container:
	@LDFLAGS="$(LDFLAGS)" REPO_DIR=$(REPO_DIR) PREFIX=$(PREFIX) VERSION=$(VERSION) ./hack/make/test-proxy-container.sh

test-proxy: peg $(REPO_DIR)/cmd/test-proxy/metric_grammar.peg.go clean fmt vet
	GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(OUT_DIR)/$(ARCH)/test-proxy ./cmd/test-proxy/...

peg:
	@which peg > /dev/null || \
		(cd $(REPO_DIR)/..; GOARCH=$(ARCH) CGO_ENABLED=0 go get -u github.com/pointlander/peg)

%.peg.go: %.peg
	peg -switch -inline $<

#This rule need to be run on RHEL with podman installed.
container_rhel: build
	@OUT_DIR=$(OUT_DIR) ARCH=$(ARCH) BINARY_NAME=$(BINARY_NAME) TEMP_DIR=$(TEMP_DIR) PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) OVERRIDE_IMAGE_NAME=$(OVERRIDE_IMAGE_NAME) ./hack/make/container_rhel.sh

clean:
	@rm -f $(OUT_DIR)/$(ARCH)/$(BINARY_NAME)
	@rm -f $(OUT_DIR)/$(ARCH)/$(BINARY_NAME)-test
	@rm -f $(OUT_DIR)/$(ARCH)/test-proxy

deploy-targets:
	@(cd $(DEPLOY_DIR) && ./deploy-targets.sh)

clean-targets:
	@(cd $(DEPLOY_DIR) && ./uninstall-targets.sh)

token-check:
	@if [ -z ${WAVEFRONT_TOKEN} ]; then echo "Need to set WAVEFRONT_TOKEN" && exit 1; fi

k9s:
	watch -n 1 k9s

clean-deployment:
	@DEPLOY_DIR=$(DEPLOY_DIR) KUSTOMIZE_DIR=$(KUSTOMIZE_DIR) ./hack/make/clean-deployment.sh

k8s-env:
	@./hack/make/k8s-env.sh

clean-cluster: clean-targets clean-deployment

nuke-kind:
	kind delete cluster
	kind create cluster

# TODO: I propose this be 'target-kind'
kind-connect-to-cluster:
	kubectl config use kind-kind

target-gke:
	gcloud config set project $(GCP_PROJECT)
	gcloud auth configure-docker --quiet

target-eks:
	export AWS_PROFILE=$(AWS_PROFILE) # TODO: doesn't work
	aws sts get-caller-identity
	aws eks --region $(AWS_REGION) update-kubeconfig --name k8s-saas-team-dev --profile $(AWS_PROFILE)
	aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(ECR_ENDPOINT)

gke-cluster-name-check:
	@if [ -z ${GKE_CLUSTER_NAME} ]; then echo "Need to set GKE_CLUSTER_NAME" && exit 1; fi

gke-connect-to-cluster: gke-cluster-name-check
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/gke-connect-to-cluster.sh

delete-gke-cluster: gke-cluster-name-check target-gke
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) ./hack/make/delete-gke-cluster.sh

create-gke-cluster: gke-cluster-name-check target-gke
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/create-gke-cluster.sh

delete-images-gcr:
	@GCP_PROJECT=$(GCP_PROJECT) VERSION=$(VERSION) ./hack/make/delete-images-gcr.sh

push-to-gcr:
	@IMAGE_PREFIX=$(PREFIX) IMAGE_VERSION=$(VERSION) REPO_ENDPOINT='us.gcr.io' REPO_PREFIX=$(GCP_PROJECT) ./hack/make/push-container.sh

push-to-ecr:
	@IMAGE_PREFIX=$(PREFIX) IMAGE_VERSION=$(VERSION) REPO_ENDPOINT=$(ECR_ENDPOINT) REPO_PREFIX=$(ECR_REPO_PREFIX) ./hack/make/push-container.sh

push-to-kind:
	@kind load docker-image $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) --name kind
	@kind load docker-image $(PREFIX)/test-proxy:$(VERSION) --name kind

delete-images-kind:
	@docker exec -it kind-control-plane crictl rmi $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) || true
	@docker exec -it kind-control-plane crictl rmi $(PREFIX)/test-proxy:$(VERSION) || true

push-images:
ifeq ($(K8S_ENV), GKE)
	make push-to-gcr
else
	make push-to-kind
endif

delete-images:
	@K8S_ENV=$(K8S_ENV) GCP_PROJECT=$(GCP_PROJECT) VERSION=$(VERSION) PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) ./hack/make/delete-images.sh

proxy-test: token-check
	@K8S_ENV=$(K8S_ENV) KUSTOMIZE_DIR=$(KUSTOMIZE_DIR) WAVEFRONT_TOKEN=$(WAVEFRONT_TOKEN) VERSION=$(VERSION) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/proxy-test.sh

#Testing deployment and configuration changes, no code changes
deploy-test: token-check k8s-env clean-deployment deploy-targets push-images proxy-test

#Testing code, configuration and deployment changes
integration-test: token-check k8s-env clean-deployment deploy-targets build tests containers delete-images push-images proxy-test

.PHONY: all fmt container clean release
