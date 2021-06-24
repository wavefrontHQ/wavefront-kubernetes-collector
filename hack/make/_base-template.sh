#!/usr/bin/env bash
source hack/make/_script-tools.sh

function print_usage_and_exit() {
    red "Failure: $1"
    echo "Usage: $0 <var1> <var2> <var3> <var4>"
    exit 1
}

VAR_1=$1
VAR_2=$2
VAR_3=$3
VAR_4=$4

if [ "$#" -ne 4 ]; then
    print_usage_and_exit "Illegal number of parameters"
fi