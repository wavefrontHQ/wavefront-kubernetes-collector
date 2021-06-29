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
	@./hack/make/fmt.sh

tests:
	@./hack/make/tests.sh

build: clean fmt vet
	@ARCH=$(ARCH) LDFLAGS="$(LDFLAGS)" OUT_DIR=$(OUT_DIR) BINARY_NAME=$(BINARY_NAME) ./hack/make/build.sh

vet:
	@./hack/make/vet.sh

# test driver for local development
driver: clean fmt
	@ARCH=$(ARCH) LDFLAGS="$(LDFLAGS)" OUT_DIR=$(OUT_DIR) BINARY_NAME=$(BINARY_NAME) ./hack/make/driver.sh

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
	@ARCH=$(ARCH) LDFLAGS="$(LDFLAGS)" OUT_DIR=$(OUT_DIR) ./hack/make/test-proxy.sh

peg:
	@REPO_DIR=$(REPO_DIR) ARCH=$(ARCH) ./hack/make/peg.sh

%.peg.go: %.peg
	peg -switch -inline $<

#This rule need to be run on RHEL with podman installed.
container_rhel: build
	@OUT_DIR=$(OUT_DIR) ARCH=$(ARCH) BINARY_NAME=$(BINARY_NAME) TEMP_DIR=$(TEMP_DIR) PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) OVERRIDE_IMAGE_NAME=$(OVERRIDE_IMAGE_NAME) ./hack/make/container_rhel.sh

clean:
	@OUT_DIR=$(OUT_DIR) ARCH=$(ARCH) BINARY_NAME=$(BINARY_NAME) ./hack/make/clean.sh

deploy-targets:
	@DEPLOY_DIR=$(DEPLOY_DIR) ./hack/make/deploy-targets.sh

clean-targets:
	@DEPLOY_DIR=$(DEPLOY_DIR) ./hack/make/clean-targets.sh

token-check:
	@./hack/make/token-check.sh

k9s:
	watch -n 1 k9s

clean-deployment:
	@DEPLOY_DIR=$(DEPLOY_DIR) KUSTOMIZE_DIR=$(KUSTOMIZE_DIR) ./hack/make/clean-deployment.sh

k8s-env:
	@./hack/make/k8s-env.sh

clean-cluster: clean-targets clean-deployment

nuke-kind:
	@./hack/make/nuke-kind.sh

# TODO: I propose this be 'target-kind'
kind-connect-to-cluster:
	@./hack/make/kind-connect-to-cluster.sh

target-gke:
	@GCP_PROJECT=$(GCP_PROJECT) ./hack/make/target-gke.sh

target-eks:
	@AWS_PROFILE=$(AWS_PROFILE) AWS_REGION=$(AWS_REGION) ECR_ENDPOINT=$(ECR_ENDPOINT) ./hack/make/target-eks.sh

gke-cluster-name-check:
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) ./hack/make/gke-cluster-name-check.sh

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
	@PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) ./hack/make/push-to-kind.sh

delete-images-kind:
	@PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) VERSION=$(VERSION) ./hack/make/delete-images-kind.sh

push-images:
	@K8S_ENV=$(K8S_ENV) PREFIX=$(PREFIX) VERSION=$(VERSION) GCP_PROJECT=$(GCP_PROJECT) DOCKER_IMAGE=$(DOCKER_IMAGE) ./hack/make/push-images.sh

delete-images:
	@K8S_ENV=$(K8S_ENV) GCP_PROJECT=$(GCP_PROJECT) VERSION=$(VERSION) PREFIX=$(PREFIX) DOCKER_IMAGE=$(DOCKER_IMAGE) ./hack/make/delete-images.sh

proxy-test: token-check
	@K8S_ENV=$(K8S_ENV) KUSTOMIZE_DIR=$(KUSTOMIZE_DIR) WAVEFRONT_TOKEN=$(WAVEFRONT_TOKEN) VERSION=$(VERSION) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/proxy-test.sh

#Testing deployment and configuration changes, no code changes
deploy-test: token-check k8s-env clean-deployment deploy-targets push-images proxy-test

#Testing code, configuration and deployment changes
integration-test: token-check k8s-env clean-deployment deploy-targets build tests containers delete-images push-images proxy-test

.PHONY: all fmt container clean release
