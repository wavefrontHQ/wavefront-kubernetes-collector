#!/usr/bin/env bash
source hack/make/_script-tools.sh

function print_usage_and_exit() {
    red "Failure: $1"
    echo "Usage: $0 <var1> <var2> <var3> <var4>"
    exit 1
}

OUT_DIR=$1
ARCH=$2
BINARY_NAME=$3

if [ "$#" -ne 3 ]; then
    print_usage_and_exit "Illegal number of parameters"
fi

rm -f ${OUT_DIR}/${ARCH}/${BINARY_NAME}
rm -f ${OUT_DIR}/${ARCH}/${BINARY_NAME}-test
rm -f ${OUT_DIR}/${ARCH}/test-proxy