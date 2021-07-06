#!/bin/bash -e
source ../deploy/k8s-utils.sh
source ../make/_script-tools.sh

# This script automates the functional testing of the collector

DEFAULT_VERSION="1.3.6"
DEFAULT_DOCKER_HOST="wavefronthq"

WAVEFRONT_CLUSTER=$1
API_TOKEN=$2
VERSION=$3
DOCKER_HOST=$4

if [[ -z ${VERSION} ]] ; then
    VERSION=${DEFAULT_VERSION}
fi

if [[ -z ${DOCKER_HOST} ]] ; then
    DOCKER_HOST=${DEFAULT_DOCKER_HOST}
fi

echo "deploying collector $IMAGE_NAME $VERSION"

env USE_TEST_PROXY=true ./deploy.sh -c "$WAVEFRONT_CLUSTER" -t "$API_TOKEN" -v $VERSION -d $DOCKER_HOST

NS=wavefront-collector

echo "deploying configuration for additional targets"

kubectl config set-context --current --namespace="$NS"
kubectl apply -f ../deploy/mysql-config.yaml
kubectl apply -f ../deploy/memcached-config.yaml
kubectl config set-context --current --namespace=default

wait_for_cluster_ready

kubectl --namespace "$NS" port-forward deploy/wavefront-proxy 8888 &
trap 'kill $(jobs -p)' EXIT

echo "waiting for logs..."
sleep 32

DIR=$(dirname "$0")
RES=$(mktemp)
while true ; do # wait until we get a good connection
  RES_CODE=$(curl --silent --output "$RES" --write-out "%{http_code}" --data-binary "@$DIR/files/metrics.jsonl" "http://localhost:8888/metrics/diff")
  [[ $RES_CODE -eq 0 ]] || break
done

if [[ $RES_CODE -gt 399 ]] ; then
  red "INVALID METRICS"
  jq -r '.[]' "${RES}"
  exit 1
fi

DIFF_COUNT=$(jq "(.Missing | length) + (.Extra | length)" "$RES")
EXIT_CODE=0
if [[ $DIFF_COUNT -gt 0 ]] ; then
  red "MISSING: $(jq "(.Missing | length)" "$RES")"
  jq -c '.Missing[]' "$RES" | sort > missing.jsonl
  red "Extra: $(jq "(.Extra | length)" "$RES")"
  jq -c '.Extra[]' "$RES" | sort > extra.jsonl
  red "FAILED: METRICS OUTPUT DID NOT MATCH EXACTLY"
  echo "$RES"
  if which pbcopy > /dev/null; then
    echo "$RES" | pbcopy
  fi
  EXIT_CODE=1
else
  green "SUCCEEDED"
fi

env USE_TEST_PROXY=false ./deploy.sh -c "$WAVEFRONT_CLUSTER" -t "$API_TOKEN" -v $VERSION -d $DOCKER_HOST

exit "$EXIT_CODE"
