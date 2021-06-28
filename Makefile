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
	# Run build in a container in order to have reproducible builds
	docker build \
	--build-arg BINARY_NAME=$(BINARY_NAME) --build-arg LDFLAGS="$(LDFLAGS)" \
	--pull -t $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) .
ifneq ($(OVERRIDE_IMAGE_NAME),)
	docker tag $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) $(OVERRIDE_IMAGE_NAME)
endif

github-release:
	curl -X POST -H "Content-Type:application/json" -H "Authorization: token $(GITHUB_TOKEN)" \
		-d '{"tag_name":"v$(VERSION)", "target_commitish":"$(GIT_BRANCH)", "name":"Release v$(VERSION)", "body": "Description for v$(VERSION)", "draft": true, "prerelease": false}' "https://api.github.com/repos/$(GIT_HUB_REPO)/releases"

release:
	docker buildx create --use --node wavefront_collector_builder
ifeq ($(RELEASE_TYPE), release)
	docker buildx build --platform linux/amd64,linux/arm64 --push \
	--build-arg BINARY_NAME=$(BINARY_NAME) --build-arg LDFLAGS="$(LDFLAGS)" \
	--pull -t $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) -t $(PREFIX)/$(DOCKER_IMAGE):latest .
else
	docker buildx build --platform linux/amd64,linux/arm64 --push \
	--build-arg BINARY_NAME=$(BINARY_NAME) --build-arg LDFLAGS="$(LDFLAGS)" \
	--pull -t $(PREFIX)/$(DOCKER_IMAGE):$(VERSION)-rc-$(RC_NUMBER) .
endif

test-proxy-container:
	docker build \
	--build-arg BINARY_NAME=test-proxy --build-arg LDFLAGS="$(LDFLAGS)" \
	--pull -f $(REPO_DIR)/Dockerfile.test-proxy \
	-t $(PREFIX)/test-proxy:$(VERSION) .

test-proxy: peg $(REPO_DIR)/cmd/test-proxy/metric_grammar.peg.go clean fmt vet
	GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(OUT_DIR)/$(ARCH)/test-proxy ./cmd/test-proxy/...

peg:
	@which peg > /dev/null || \
		(cd $(REPO_DIR)/..; GOARCH=$(ARCH) CGO_ENABLED=0 go get -u github.com/pointlander/peg)

%.peg.go: %.peg
	peg -switch -inline $<

#This rule need to be run on RHEL with podman installed.
container_rhel: build
	cp $(OUT_DIR)/$(ARCH)/$(BINARY_NAME) $(TEMP_DIR)
	cp LICENSE $(TEMP_DIR)/license.txt
	cp deploy/docker/Dockerfile-rhel $(TEMP_DIR)/Dockerfile
	cp deploy/examples/openshift-config.yaml $(TEMP_DIR)/collector.yaml
	sudo docker build --pull -t $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) $(TEMP_DIR)
ifneq ($(OVERRIDE_IMAGE_NAME),)
	sudo docker tag $(PREFIX)/$(DOCKER_IMAGE):$(VERSION) $(OVERRIDE_IMAGE_NAME)
endif

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
	aws eks --region $(AWS_REGION) update-kubeconfig --name k8s-saas-team-dev --profile $(AWS_PROFILE)
	aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(ECR_ENDPOINT)

gke-cluster-name-check:
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) ./hack/make/gke-cluster-name-check.sh

gke-connect-to-cluster: gke-cluster-name-check
	@GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/gke-connect-to-cluster.sh

delete-gke-cluster: gke-cluster-name-check target-gke
	GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) ./hack/make/delete-gke-cluster.sh

create-gke-cluster: gke-cluster-name-check target-gke
	GKE_CLUSTER_NAME=$(GKE_CLUSTER_NAME) GCP_PROJECT=$(GCP_PROJECT) ./hack/make/create-gke-cluster.sh

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
ifeq ($(K8S_ENV), GKE)
	make push-to-gcr
else
	make push-to-kind
endif

delete-images:
ifeq ($(K8S_ENV), GKE)
	make delete-images-gcr
else
	make delete-images-kind
endif

proxy-test: token-check
ifeq ($(K8S_ENV), GKE)
	@(cd $(KUSTOMIZE_DIR) && ./test.sh nimba $(WAVEFRONT_TOKEN) $(VERSION) "us.gcr.io\/$(GCP_PROJECT)")
else
	@(cd $(KUSTOMIZE_DIR) && ./test.sh nimba $(WAVEFRONT_TOKEN) $(VERSION))
endif

#Testing deployment and configuration changes, no code changes
deploy-test: token-check k8s-env clean-deployment deploy-targets push-images proxy-test

#Testing code, configuration and deployment changes
integration-test: token-check k8s-env clean-deployment deploy-targets build tests containers delete-images push-images proxy-test

.PHONY: all fmt container clean release
