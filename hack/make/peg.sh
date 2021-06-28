#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${REPO_DIR} ]]; then
  print_msg_and_exit 'REPO_DIR required but was empty'
  #REPO_DIR=$DEFAULT_REPO_DIR
fi

if [[ -z ${ARCH} ]]; then
  print_msg_and_exit 'ARCH required but was empty'
  #ARCH=$DEFAULT_ARCH
fi

# commands ...
# Better to use the shell built-in 'command'
# shellcheck disable=SC2046
if [ ! $(command -v peg) ]; then
  red "peg not found; I shall go acquire it!"
  pushd ${REPO_DIR} || print_msg_and_exit "'pushd ${REPO_DIR}' failed"
  GOARCH=${ARCH} CGO_ENABLED=0 go get -u github.com/pointlander/peg
  popd || print_msg_and_exit "'popd ${REPO_DIR}' failed"
fi
