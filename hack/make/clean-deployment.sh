#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${DEPLOY_DIR} ]]; then
  print_msg_and_exit 'DEPLOY_DIR required but was empty'
  #DEPLOY_DIR=$DEFAULT_DEPLOY_DIR
fi

if [[ -z ${KUSTOMIZE_DIR} ]]; then
  print_msg_and_exit 'KUSTOMIZE_DIR required but was empty'
  #KUSTOMIZE_DIR=$DEFAULT_KUSTOMIZE_DIR
fi

# commands ...
pushd ${DEPLOY_DIR} || print_msg_and_exit "'pushd ${DEPLOY_DIR}' failed"
./uninstall-wavefront-helm-release.sh
popd || print_msg_and_exit "'popd ${DEPLOY_DIR}' failed"

pushd ${KUSTOMIZE_DIR} || print_msg_and_exit "'pushd ${KUSTOMIZE_DIR}' failed"
./clean-deploy.sh
popd || print_msg_and_exit "'popd ${KUSTOMIZE_DIR}' failed"
