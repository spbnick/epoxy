# Bash test framework - utilities library
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_UTIL_SH+set} ]; then
declare -r _BT_UTIL_SH=

# Shell attribute state stack
declare -a _BT_ATTR_STACK=()

# Output a backtrace
# Args: [start_frame]
function bt_backtrace()
{
    declare start_frame=${1:-0}
    declare command="$BASH_COMMAND"
    declare -i frame
    declare -i argv=${#BASH_ARGV[@]}-1
    declare -i argc
    for ((frame = ${#BASH_LINENO[@]} - 2; frame > start_frame; frame--)); do
        echo -n "${BASH_SOURCE[frame+1]}:${BASH_LINENO[frame]}:" \
                "${FUNCNAME[frame]}"
        for ((argc = ${BASH_ARGC[frame]}; argc > 0; argc--)); do
            echo -n " ${BASH_ARGV[argv]}"
            argv=argv-1
        done
        echo
    done
}

# Output a backtrace and abort execution by sending SIGABRT to $BASHPID,
# optionally outputting a message to stderr.
# Args [message...]
function bt_abort()
{
    {
        echo "Backtrace:"
        bt_backtrace
        if [ $# == 0 ]; then
            echo "Aborted"
        else
            echo "$@"
        fi
    } >&2
    kill -s SIGABRT $BASHPID
}

# Evaluate and execute an assertion verification command; abort execution, if
# it fails.
# Args [eval_arg...]
function bt_assert()
{
    eval "$@" || bt_abort "Assertion failed: $@"
}

# Push values to an array-based stack.
# Args: stack value...
function bt_arrstack_push()
{
    declare -r _stack="$1"
    shift
    while (( $# > 0 )); do
        eval "$_stack[\${#$_stack[@]}]=\"\$1\""
        shift
    done
}

# Get a value from the top of an array-based stack.
# Args: stack
function bt_arrstack_peek()
{
    declare -r _stack="$1"
    if eval "test \${#$_stack[@]} -eq 0"; then
        bt_abort "Not enough values in an array-based stack"
    fi
    eval "echo \"\${$_stack[\${#$_stack[@]}-1]}\""
}

# Pop values from an array-based stack.
# Args: stack [num_values]
function bt_arrstack_pop()
{
    declare -r _stack="$1"
    declare _num_values="${2:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        bt_abort "Invalid number of values: $_num_values"
    fi

    while (( _num_values > 0 )); do
        if eval "test \${#$_stack[@]} -eq 0"; then
            bt_abort "Not enough values in an array-based stack"
        fi
        eval "unset $_stack[\${#$_stack[@]}-1]"
        _num_values=$((_num_values-1))
    done
}

# Push values to a string-based stack.
# Args: _stack _sep _value...
function bt_strstack_push()
{
    declare -r _stack="$1"; shift
    declare -r _sep="$1"; shift
    while (( $# > 0 )); do
        if [[ "$1" == *[$_sep[:cntrl:]]* ]]; then
            bt_abort "Invalid string-based stack value: $1"
        fi
        eval "$_stack=\"\$$_stack$_sep$1\"";
        shift
    done
}

# Get a value from the top of a string-based stack.
# Args: _stack _sep
function bt_strstack_peek()
{
    declare -r _stack="$1"
    declare -r _sep="$2"
    if eval "test -z \"\$$_stack\""; then
        bt_abort "Not enough values in a string-based stack"
    fi
    eval "echo \"\${$_stack##*$_sep}\""
}

# Pop values from a string-based stack.
# Args: _stack _sep [_num_values]
function bt_strstack_pop()
{
    declare -r _stack="$1"
    declare -r _sep="$2"
    declare _num_values="${3:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        bt_abort "Invalid number of values: $_num_values"
    fi

    while (( _num_values > 0 )); do
        if eval "test -z \"\$$_stack\""; then
            bt_abort "Not enough values in a string-based stack"
        fi
        eval "$_stack=\"\${$_stack%$_sep*}\""
        _num_values=$((_num_values-1))
    done
}

# Set shell attributes using format of the SHELLOPTS variable
# Args: shellopts
function bt_attrs_set_shellopts()
{
    declare -r shellopts="$1"
    declare -r normal_shellopts=":$shellopts:"
    declare attr
    declare state

    while read -r attr state; do
        if [[ "$normal_shellopts" == *:"$attr":* ]]; then
            set -o $attr
        else
            set +o $attr
        fi
    done < <(set -o)
}

# Push shell attribute state to the state stack, optionally invoke "set".
# Args: [set_arg...]
function bt_attrs_push()
{
    bt_arrstack_push _BT_ATTR_STACK "$SHELLOPTS"
    if [ $# != 0 ]; then
        set "$@"
    fi
}

# Pop shell attribute state from the state stack.
function bt_attrs_pop()
{
    bt_attrs_set_shellopts "`bt_arrstack_peek _BT_ATTR_STACK`"
    bt_arrstack_pop _BT_ATTR_STACK
}

# Convert pipestatus array elements to a single status code.
# Args: [status...]
function bt_pipestatus_to_status()
{
    if [ -o pipefail ]; then
        declare last=0
        for s in "$@"; do
            if [ "$s" != 0 ]; then
                last="$s"
            fi
        done
        echo "$last"
    else
        shift $(($# - 1))
        echo "$1"
    fi
}

# Check if two exit statuses or pipestatuses are equal.
# Args: s1 s2
function bt_pipestatus_eq()
{
    if [[ "$1" == *" "* ]]; then
        [[ "$2" == *" "* && "$1" == "$2" ||
           `bt_pipestatus_to_status $1` == "$2" ]]
    else
        [[ "$2" == *" "* && "$1" == `bt_pipestatus_to_status $2` ||
           "$1" == "$2" ]]
    fi
}

fi # _BT_UTIL_SH
