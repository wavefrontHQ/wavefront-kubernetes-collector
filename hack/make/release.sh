#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${BINARY_NAME} ]]; then
  print_msg_and_exit 'BINARY_NAME required but was empty'
  #BINARY_NAME=$DEFAULT_BINARY_NAME
fi

if [[ -z ${LDFLAGS} ]]; then
  print_msg_and_exit 'LDFLAGS required but was empty'
  #LDFLAGS=$DEFAULT_LDFLAGS
fi

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

if [[ -z ${RC_NUMBER} ]]; then
  print_msg_and_exit 'RC_NUMBER required but was empty'
  #RC_NUMBER=$DEFAULT_RC_NUMBER
fi

# commands ...
docker buildx create --use --node wavefront_collector_builder
if [ ${RELEASE_TYPE} == "release" ]; then
  docker buildx build --platform linux/amd64,linux/arm64 --push \
    --build-arg BINARY_NAME=${BINARY_NAME} --build-arg LDFLAGS="${LDFLAGS}" \
    --pull -t ${PREFIX}/${DOCKER_IMAGE}:${VERSION} -t ${PREFIX}/${DOCKER_IMAGE}:latest .
else
  docker buildx build --platform linux/amd64,linux/arm64 --push \
    --build-arg BINARY_NAME=${BINARY_NAME} --build-arg LDFLAGS="${LDFLAGS}" \
    --pull -t ${PREFIX}/${DOCKER_IMAGE}:${VERSION}-rc-${RC_NUMBER} .
fi
