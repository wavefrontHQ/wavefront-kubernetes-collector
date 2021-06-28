#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${DEPLOY_DIR} ]]; then
  print_msg_and_exit 'DEPLOY_DIR required but was empty'
  #DEPLOY_DIR=$DEFAULT_DEPLOY_DIR
fi

# commands ...
pushd ${DEPLOY_DIR} || print_msg_and_exit "'pushd ${DEPLOY_DIR}' failed"
./deploy-targets.sh
popd || print_msg_and_exit "'popd ${DEPLOY_DIR}' failed"
