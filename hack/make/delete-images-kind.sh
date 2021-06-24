#!/usr/bin/env bash
source hack/make/_script-tools.sh

function print_usage_and_exit() {
    red "Failure: $1"
    echo "Usage: $0 <prefix> <docker image> <version>"
    exit 1
}

PREFIX=$1
DOCKER_IMAGE=$2
VERSION=$3

# Note: make sure this is equal to the number of variables defined above
NUM_ARGS_EXPECTED=3
if [ "$#" -ne $NUM_ARGS_EXPECTED ]; then
    print_usage_and_exit "Illegal number of parameters"
fi

docker exec -it kind-control-plane crictl rmi ${PREFIX}/${DOCKER_IMAGE}:${VERSION} || true
kind load docker-image ${PREFIX}/${DOCKER_IMAGE}:${VERSION} --name kind

docker exec -it kind-control-plane crictl rmi ${PREFIX}/test-proxy:${VERSION} || true
kind load docker-image ${PREFIX}/test-proxy:${VERSION} --name kind