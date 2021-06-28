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

# commands ...
# Run build in a container in order to have reproducible builds
docker build \
  --build-arg BINARY_NAME=${BINARY_NAME} --build-arg LDFLAGS="${LDFLAGS}" \
  --pull -t ${PREFIX}/${DOCKER_IMAGE}:${VERSION} .

if [[ -n ${OVERRIDE_IMAGE_NAME} ]]; then
  docker tag ${PREFIX}/${DOCKER_IMAGE}:${VERSION} ${OVERRIDE_IMAGE_NAME}
fi
