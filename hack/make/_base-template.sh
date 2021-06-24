#!/usr/bin/env bash
source hack/make/_script-tools.sh

function print_usage_and_exit() {
    red "Failure: $1"
    echo "Usage: $0 <var1> <var2> <var3> <var4>"
    exit 1
}

# Note: order input arguments in the order in which they appear in the commands
var1=$1
var2=$2
var3=$3
var4=$4

# Note: make sure this is equal to the number of variables defined above
NUM_ARGS_EXPECTED=4
if [ "$#" -ne $NUM_ARGS_EXPECTED ]; then
    print_usage_and_exit "Illegal number of parameters"
fi

# command ...
