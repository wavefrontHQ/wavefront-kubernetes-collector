#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${GCP_PROJECT} ]]; then
  print_msg_and_exit 'GCP_PROJECT required but was empty'
  #GCP_PROJECT=DEFAULT_GCP_PROJECT
fi

if [[ -z ${VERSION} ]]; then
  print_msg_and_exit 'VERSION required but was empty'
  #VERSION=DEFAULT_VERSION
fi

# commands ...

gcloud container images delete us.gcr.io/${GCP_PROJECT}/test-proxy:${VERSION} --quiet || true
gcloud container images delete us.gcr.io/${GCP_PROJECT}/wavefront-kubernetes-collector:${VERSION} --quiet || true
