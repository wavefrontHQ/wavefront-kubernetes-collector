#!/usr/bin/env bash
source hack/make/_script-tools.sh

# commands ...
if [ -z ${GKE_CLUSTER_NAME} ]; then
  print_msg_and_exit "Need to set GKE_CLUSTER_NAME"
fi