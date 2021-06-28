#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${IMAGE_PREFIX} ]]; then
  print_msg_and_exit 'IMAGE_PREFIX required but was empty'
  #IMAGE_PREFIX=$DEFAULT_IMAGE_PREFIX
fi

if [[ -z ${IMAGE_VERSION} ]]; then
  print_msg_and_exit 'IMAGE_VERSION required but was empty'
  #IMAGE_VERSION=$DEFAULT_IMAGE_VERSION
fi

if [[ -z ${REPO_ENDPOINT} ]]; then
  print_msg_and_exit 'REPO_ENDPOINT required but was empty'
  #REPO_ENDPOINT=$DEFAULT_REPO_ENDPOINT
fi

if [[ -z ${REPO_PREFIX} ]]; then
  print_msg_and_exit 'REPO_PREFIX required but was empty'
  #REPO_PREFIX=$DEFAULT_REPO_PREFIX
fi

# commands ...

docker tag ${IMAGE_PREFIX}/test-proxy:${IMAGE_VERSION} ${REPO_ENDPOINT}/${REPO_PREFIX}/test-proxy:${IMAGE_VERSION}
docker push ${REPO_ENDPOINT}/${REPO_PREFIX}/test-proxy:${IMAGE_VERSION}

docker tag ${IMAGE_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION} ${REPO_ENDPOINT}/${REPO_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION}
docker push ${REPO_ENDPOINT}/${REPO_PREFIX}/wavefront-kubernetes-collector:${IMAGE_VERSION}
