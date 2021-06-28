#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${K8S_ENV} ]]; then
  print_msg_and_exit 'K8S_ENV required but was empty'
  #K8S_ENV=$DEFAULT_K8S_ENV
fi

if [[ -z ${PREFIX} ]]; then
  print_msg_and_exit 'PREFIX required but was empty'
  #PREFIX=$DEFAULT_PREFIX
fi

if [[ -z ${VERSION} ]]; then
  print_msg_and_exit 'VERSION required but was empty'
  #VERSION=$DEFAULT_VERSION
fi

if [[ -z ${GCP_PROJECT} ]]; then
  print_msg_and_exit 'GCP_PROJECT required but was empty'
  #GCP_PROJECT=$DEFAULT_GCP_PROJECT
fi

if [[ -z ${DOCKER_IMAGE} ]]; then
  print_msg_and_exit 'DOCKER_IMAGE required but was empty'
  #DOCKER_IMAGE=$DEFAULT_DOCKER_IMAGE
fi

# commands ...
if [ ${K8S_ENV} == "GKE" ]; then
  ./hack/make/push-container.sh
else
  ./hack/make/push-to-kind.sh
fi
