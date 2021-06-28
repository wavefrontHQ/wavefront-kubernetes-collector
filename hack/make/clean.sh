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

# commands ...
rm -f ${OUT_DIR}/${ARCH}/${BINARY_NAME}
rm -f ${OUT_DIR}/${ARCH}/${BINARY_NAME}-test
rm -f ${OUT_DIR}/${ARCH}/test-proxy
