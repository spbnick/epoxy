#
# Utilities library
#
# Copyright (c) 2012-2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_UTIL_SH+set} ]; then
declare -r _EP_UTIL_SH=

# Shell attribute state stack
declare -a _EP_ATTR_STACK=()

# The PID ep_abort should send SIGABRT to, or empty, meaning $$.
declare EP_ABORT_PID=

# Output a backtrace
# Args: [start_frame]
function ep_backtrace()
{
    declare start_frame=${1:-0}
    declare frame
    declare argv=0
    declare argc

    for ((frame = 0; frame < ${#BASH_LINENO[@]} - 1; frame++)); do
        if ((frame > start_frame)); then
            echo -n "${BASH_SOURCE[frame+1]}:${BASH_LINENO[frame]}:" \
                    "${FUNCNAME[frame]}"
            for ((argc = ${BASH_ARGC[frame]}; argc > 0; argc--)); do
                echo -n " ${BASH_ARGV[argv + argc - 1]}"
            done
            echo
        fi
        argv=$((argv + BASH_ARGC[frame]))
    done
}

# Abort execution by sending SIGABRT to EP_ABORT_PID, or to $$ if not set,
# optionally outputting a message.
# Args: [message...]
function ep_abort()
{
    declare pid=

    if [ -n "${EP_ABORT_PID:+set}" ]; then
        pid="$EP_ABORT_PID"
    else
        pid="$$"
    fi
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    kill -s SIGABRT "$pid"
}

# Abort execution if an assertion is invalid (a command fails).
# Args: [command [arg...]]
function ep_abort_if_not()
{
    declare _status=
    ep_attrs_push +o errexit
    (
        ep_attrs_pop
        "$@"
    )
    _status=$?
    ep_attrs_pop
    if [ $_status != 0 ]; then
        declare -r _loc="${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}"
        ep_abort "$_loc: Assertion failed: $@"
    fi
}

# Push values to an array-based stack.
# Args: stack value...
function ep_arrstack_push()
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
function ep_arrstack_peek()
{
    declare -r _stack="$1"
    if eval "test \${#$_stack[@]} -eq 0"; then
        ep_abort "Not enough values in an array-based stack"
    fi
    eval "echo \"\${$_stack[\${#$_stack[@]}-1]}\""
}

# Pop values from an array-based stack.
# Args: stack [num_values]
function ep_arrstack_pop()
{
    declare -r _stack="$1"
    declare _num_values="${2:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        ep_abort "Invalid number of values: $_num_values"
    fi

    while (( _num_values > 0 )); do
        if eval "test \${#$_stack[@]} -eq 0"; then
            ep_abort "Not enough values in an array-based stack"
        fi
        eval "unset $_stack[\${#$_stack[@]}-1]"
        _num_values=$((_num_values-1))
    done
}

# Push values to a string-based stack.
# Args: _stack _sep _value...
function ep_strstack_push()
{
    declare -r _stack="$1"; shift
    declare -r _sep="$1"; shift
    while (( $# > 0 )); do
        if [[ "$1" == *[$_sep[:cntrl:]]* ]]; then
            ep_abort "Invalid string-based stack value: $1"
        fi
        eval "$_stack=\"\${$_stack}\${_sep}\${1}\"";
        shift
    done
}

# Get a value from the top of a string-based stack.
# Args: _stack _sep
function ep_strstack_peek()
{
    declare -r _stack="$1"
    declare -r _sep="$2"
    if eval "test -z \"\$$_stack\""; then
        ep_abort "Not enough values in a string-based stack"
    fi
    eval "echo \"\${$_stack##*$_sep}\""
}

# Pop values from a string-based stack.
# Args: _stack _sep [_num_values]
function ep_strstack_pop()
{
    declare -r _stack="$1"
    declare -r _sep="$2"
    declare _num_values="${3:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        ep_abort "Invalid number of values: $_num_values"
    fi

    while (( _num_values > 0 )); do
        if eval "test -z \"\$$_stack\""; then
            ep_abort "Not enough values in a string-based stack"
        fi
        eval "$_stack=\"\${$_stack%$_sep*}\""
        _num_values=$((_num_values-1))
    done
}

# Set shell attributes using format of the SHELLOPTS variable
# Args: shellopts
function ep_attrs_set_shellopts()
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
function ep_attrs_push()
{
    # Using process substitution instead of command substitution,
    # because the latter resets errexit.
    declare opts
    if read -rd '' opts < <(set +o); [ $? != 1 ]; then
        ep_abort Failed to read attrs
    fi
    ep_arrstack_push _EP_ATTR_STACK "$opts"
    if [ $# != 0 ]; then
        set "$@"
    fi
}

# Pop shell attribute state from the state stack.
function ep_attrs_pop()
{
    eval "`ep_arrstack_peek _EP_ATTR_STACK`"
    ep_arrstack_pop _EP_ATTR_STACK
}

# Check if a boolean value is valid
# Args: value
function ep_bool_is_valid()
{
    ep_abort_if_not [ ${1+set} ]
    [ "$1" == "true" ] || [ "$1" == "false" ]
}

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    ep_abort_if_not Enhanced getopt not found
fi

fi # _EP_UTIL_SH
