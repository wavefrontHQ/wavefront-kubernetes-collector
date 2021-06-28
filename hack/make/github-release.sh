#!/usr/bin/env bash
source hack/make/_script-tools.sh

if [[ -z ${GITHUB_TOKEN} ]]; then
  print_msg_and_exit 'GITHUB_TOKEN required but was empty'
  #GITHUB_TOKEN=$DEFAULT_GITHUB_TOKEN
fi

if [[ -z ${VERSION} ]]; then
  print_msg_and_exit 'VERSION required but was empty'
  #VERSION=$DEFAULT_VERSION
fi

if [[ -z ${GIT_BRANCH} ]]; then
  print_msg_and_exit 'GIT_BRANCH required but was empty'
  #GIT_BRANCH=$DEFAULT_GIT_BRANCH
fi

if [[ -z ${GIT_HUB_REPO} ]]; then
  print_msg_and_exit 'GIT_HUB_REPO required but was empty'
  #GIT_HUB_REPO=$DEFAULT_GIT_HUB_REPO
fi

# commands ...
curl -X POST -H "Content-Type:application/json" -H "Authorization: token ${GITHUB_TOKEN}" \
  -d "{\"tag_name\":\"v${VERSION}\", \"target_commitish\":\"${GIT_BRANCH}\", \"name\":\"Release v${VERSION}\", \"body\": \"Description for v${VERSION}\", \"draft\": true, \"prerelease\": false}" "https://api.github.com/repos/${GIT_HUB_REPO}/releases"
