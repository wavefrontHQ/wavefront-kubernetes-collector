#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${GKE_CLUSTER_NAME} ]]; then
  print_msg_and_exit 'GKE_CLUSTER_NAME required but was empty'
  #GKE_CLUSTER_NAME=$DEFAULT_GKE_CLUSTER_NAME
fi

# commands ...
echo "Deleting GKE K8s Cluster: ${GKE_CLUSTER_NAME}"
gcloud container clusters delete ${GKE_CLUSTER_NAME} --region=us-central1-c --quiet
