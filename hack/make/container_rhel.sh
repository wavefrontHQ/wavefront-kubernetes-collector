#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${OUT_DIR} ]]; then
  print_msg_and_exit 'OUT_DIR required but was empty'
  #OUT_DIR=$DEFAULT_OUT_DIR
fi

if [[ -z ${ARCH} ]]; then
  print_msg_and_exit 'ARCH required but was empty'
  #ARCH=$DEFAULT_ARCH
fi

if [[ -z ${BINARY_NAME} ]]; then
  print_msg_and_exit 'BINARY_NAME required but was empty'
  #BINARY_NAME=$DEFAULT_BINARY_NAME
fi

if [[ -z ${TEMP_DIR} ]]; then
  print_msg_and_exit 'TEMP_DIR required but was empty'
  #TEMP_DIR=$DEFAULT_TEMP_DIR
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
cp ${OUT_DIR}/${ARCH}/${BINARY_NAME} ${TEMP_DIR}
cp LICENSE ${TEMP_DIR}/license.txt
cp deploy/docker/Dockerfile-rhel ${TEMP_DIR}/Dockerfile
cp deploy/examples/openshift-config.yaml ${TEMP_DIR}/collector.yaml
sudo docker build --pull -t ${PREFIX}/${DOCKER_IMAGE}:${VERSION} ${TEMP_DIR}

if [[ -n ${OVERRIDE_IMAGE_NAME} ]]; then
  sudo docker tag ${PREFIX}/${DOCKER_IMAGE}:${VERSION} ${OVERRIDE_IMAGE_NAME}
fi
