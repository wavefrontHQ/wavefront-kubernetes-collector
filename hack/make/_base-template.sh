#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${VAR1} ]]; then
    print_msg_and_exit 'VAR1 required but was empty'
    #VAR1=DEFAULT_VAR1
fi

if [[ -z ${VAR2} ]]; then
    print_msg_and_exit 'VAR2 required but was empty'
    #VAR2=DEFAULT_VAR2
fi

if [[ -z ${VAR3} ]]; then
    print_msg_and_exit 'VAR3 required but was empty'
    #VAR3=DEFAULT_VAR3
fi

if [[ -z ${VAR4} ]]; then
    print_msg_and_exit 'VAR4 required but was empty'
    #VAR4=DEFAULT_VAR4
fi

# commands ...
