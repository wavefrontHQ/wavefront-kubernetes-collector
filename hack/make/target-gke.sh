#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${GCP_PROJECT} ]]; then
  print_msg_and_exit 'GCP_PROJECT required but was empty'
  #GCP_PROJECT=$DEFAULT_GCP_PROJECT
fi

# commands ...
gcloud config set project ${GCP_PROJECT}
gcloud auth configure-docker --quiet
