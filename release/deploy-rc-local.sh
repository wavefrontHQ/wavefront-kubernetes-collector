#!/usr/bin/env bash

function print_msg_and_exit() {
    echo -e "$1"
    exit 1
}

NS=wavefront-collector
ROOT_DIR=$(git rev-parse --show-toplevel)
TEMP_DIR=$(mktemp -d)
CURRENT_VERSION=1.4.0
VERSION=1.5.0-rc-1
WF_CLUSTER=nimba
K8S_CLUSTER=$VERSION-release-test

if [[ -z ${WAVEFRONT_TOKEN} ]] ; then
    #TODO: source these from environment variables if not provided
    print_msg_and_exit "wavefront token required"
fi

echo "Temp dir: $TEMP_DIR"

#make nuke-kind
# TODO: finish this
make target-gke
make deploy-test

# TODO: how can we use make-deploy test
# instead of all this stuff captured in here?


cp ${ROOT_DIR}/deploy/kubernetes/*  $TEMP_DIR/.

cp ${ROOT_DIR}/hack/deploy/memcached-config.yaml $TEMP_DIR/.
cp ${ROOT_DIR}/hack/deploy/mysql-config.yaml $TEMP_DIR/.
cp ${ROOT_DIR}/hack/deploy/prom-example.yaml $TEMP_DIR/.
cp ${ROOT_DIR}/hack/kustomize/base/proxy.template.yaml $TEMP_DIR/proxy.yaml

pushd $TEMP_DIR
  sed -i '' "s/YOUR_CLUSTER/${WF_CLUSTER}/g; s/YOUR_API_TOKEN/${WAVEFRONT_TOKEN}/g" ${TEMP_DIR}/proxy.yaml
  sed -i '' "s/k8s-cluster/${K8S_CLUSTER}/g" ${TEMP_DIR}/4-collector-config.yaml
  sed -i '' "s/${CURRENT_VERSION}/${VERSION}/g" ${TEMP_DIR}/5-collector-daemonset.yaml

  kubectl config set-context --current --namespace=${NS}
  kubectl apply -f $TEMP_DIR/.
  kubectl config set-context --current --namespace=default
popd

