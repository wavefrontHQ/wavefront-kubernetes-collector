#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${PREFIX} ]]; then
  print_msg_and_exit 'PREFIX required but was empty'
  #PREFIX=$DEFAULT_PREFIX
fi

if [[ -z ${DOCKER_IMAGE} ]]; then
  print_msg_and_exit 'DOCKER_IMAGE required but was empty'
  #DOCKER_IMAGE=$DEFAULT_DOCKER_IMAGE
fi

if [[ -z ${VERSION} ]]; then
  print_msg_and_exit 'VERSION required but was empty'
  #VERSION=$DEFAULT_VERSION
fi

# commands ...

kind load docker-image ${PREFIX}/${DOCKER_IMAGE}:${VERSION} --name kind
kind load docker-image ${PREFIX}/test-proxy:${VERSION} --name kind
