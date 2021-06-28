#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${LDFLAGS} ]]; then
    print_msg_and_exit 'LDFLAGS required but was empty'
    #LDFLAGS=$DEFAULT_LDFLAGS
fi

if [[ -z ${REPO_DIR} ]]; then
    print_msg_and_exit 'REPO_DIR required but was empty'
    #REPO_DIR=$DEFAULT_REPO_DIR
fi

if [[ -z ${PREFIX} ]]; then
    print_msg_and_exit 'PREFIX required but was empty'
    #PREFIX=$DEFAULT_PREFIX
fi

if [[ -z ${VERSION} ]]; then
    print_msg_and_exit 'VERSION required but was empty'
    #VERSION=$DEFAULT_VERSION
fi

# commands ...
docker build \
	--build-arg BINARY_NAME=test-proxy --build-arg LDFLAGS="${LDFLAGS}" \
	--pull -f ${REPO_DIR}/Dockerfile.test-proxy \
	-t ${PREFIX}/test-proxy:${VERSION} .