#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${GKE_CLUSTER_NAME} ]]; then
  print_msg_and_exit 'GKE_CLUSTER_NAME required but was empty'
  #GKE_CLUSTER_NAME=$DEFAULT_GKE_CLUSTER_NAME
fi

if [[ -z ${GCP_PROJECT} ]]; then
  print_msg_and_exit 'GCP_PROJECT required but was empty'
  #GCP_PROJECT=$DEFAULT_GCP_PROJECT
fi

# commands ...
echo "Creating GKE K8s Cluster: ${GKE_CLUSTER_NAME}"
gcloud container clusters create ${GKE_CLUSTER_NAME} --machine-type=e2-standard-2 --region=us-central1-c --enable-ip-alias --create-subnetwork range=/21
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --zone us-central1-c --project ${GCP_PROJECT}
kubectl create clusterrolebinding --clusterrole cluster-admin \
  --user $$(gcloud auth list --filter=status:ACTIVE --format="value(account)") \
  clusterrolebinding
