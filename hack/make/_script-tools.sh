function green {
    echo -e $'\e[32m'$1$'\e[0m'
}

function red {
    echo -e $'\e[31m'$1$'\e[0m'
}

function print_msg_and_exit() {
    red "$1"
    exit 1
}