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
pushd_check ${DEPLOY_DIR}
./uninstall-wavefront-helm-release.sh
popd_check ${DEPLOY_DIR}

pushd_check ${KUSTOMIZE_DIR}
./clean-deploy.sh
popd_check ${KUSTOMIZE_DIR}
