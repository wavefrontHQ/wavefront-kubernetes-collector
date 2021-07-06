function green() {
  echo -e $'\e[32m'$1$'\e[0m'
}

function red() {
  echo -e $'\e[31m'$1$'\e[0m'
}

function print_msg_and_exit() {
  red "$1"
  exit 1
}

function pushd_check() {
  local d=$1
  pushd ${d} || print_msg_and_exit "Entering directory '${d}' with 'pushd' failed!"
}

function popd_check() {
  local d=$1
  popd || print_msg_and_exit "Leaving '${d}' with 'popd' failed!"
}
