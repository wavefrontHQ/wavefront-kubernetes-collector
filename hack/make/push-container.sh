#!/usr/bin/env bash
source hack/make/_script-tools.sh

function print_usage_and_exit() {
    red "Failure: $1"
    echo "Usage: $0 <image prefix> <image version> <repo endpoint> <repo prefix>"
    exit 1
}

IMAGE_PREFIX=$1
IMAGE_VERSION=$2
REPO_ENDPOINT=$3
REPO_PREFIX=$4

if [ "$#" -ne 4 ]; then
    print_usage_and_exit "Illegal number of parameters"
fi

docker tag ${IMAGE_PREFIX}/test-proxy:${IMAGE_VERSION} ${REPO_ENDPOINT}/${REPO_PREFIX}/test-proxy:${IMAGE_VERSION}
docker push ${REPO_ENDPOINT}/${REPO_PREFIX}/test-proxy:${IMAGE_VERSION}

docker tag ${IMAGE_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION} ${REPO_ENDPOINT}/${REPO_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION}
docker push ${REPO_ENDPOINT}/${REPO_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION}