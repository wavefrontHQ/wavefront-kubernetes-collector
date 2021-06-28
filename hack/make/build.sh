#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${ARCH} ]]; then
  print_msg_and_exit 'ARCH required but was empty'
  #ARCH=$DEFAULT_ARCH
fi

if [[ -z ${LDFLAGS} ]]; then
  print_msg_and_exit 'LDFLAGS required but was empty'
  #LDFLAGS=$DEFAULT_LDFLAGS
fi

if [[ -z ${OUT_DIR} ]]; then
  print_msg_and_exit 'OUT_DIR required but was empty'
  #OUT_DIR=$DEFAULT_OUT_DIR
fi

if [[ -z ${BINARY_NAME} ]]; then
  print_msg_and_exit 'BINARY_NAME required but was empty'
  #BINARY_NAME=$DEFAULT_BINARY_NAME
fi

# commands ...
GOARCH=${ARCH} CGO_ENABLED=0 go build -ldflags "${LDFLAGS}" -o ${OUT_DIR}/${ARCH}/${BINARY_NAME} ./cmd/wavefront-collector/
