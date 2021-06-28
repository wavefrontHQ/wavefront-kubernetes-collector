#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${DEPLOY_DIR} ]]; then
  print_msg_and_exit 'DEPLOY_DIR required but was empty'
  #DEPLOY_DIR=$DEFAULT_DEPLOY_DIR
fi

# commands ...
pushd_check ${DEPLOY_DIR}
./uninstall-targets.sh
popd_check ${DEPLOY_DIR}
