#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${AWS_PROFILE} ]]; then
  print_msg_and_exit 'AWS_PROFILE required but was empty'
  #AWS_PROFILE=$DEFAULT_AWS_PROFILE
fi

if [[ -z ${AWS_REGION} ]]; then
  print_msg_and_exit 'AWS_REGION required but was empty'
  #AWS_REGION=$DEFAULT_AWS_REGION
fi

if [[ -z ${ECR_ENDPOINT} ]]; then
  print_msg_and_exit 'ECR_ENDPOINT required but was empty'
  #ECR_ENDPOINT=$DEFAULT_ECR_ENDPOINT
fi

# commands ...
aws eks --region ${AWS_REGION} update-kubeconfig --name k8s-saas-team-dev --profile ${AWS_PROFILE}
aws ecr get-login-password --region ${AWS_REGION} | sudo docker login --username AWS --password-stdin ${ECR_ENDPOINT}
