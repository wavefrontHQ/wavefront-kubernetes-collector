#!/usr/bin/env bash
source hack/make/_script-tools.sh
if [ -z ${WAVEFRONT_TOKEN} ]; then
  print_msg_and_exit "Need to set WAVEFRONT_TOKEN"
fi
