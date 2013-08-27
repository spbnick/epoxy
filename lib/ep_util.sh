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

. thud_attrs.sh

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
    thud_attrs_push +o errexit
    (
        thud_attrs_pop
        "$@"
    )
    _status=$?
    thud_attrs_pop
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
        eval "$_stack+=(\"\$1\")"
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

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    ep_abort_if_not Enhanced getopt not found
fi

fi # _EP_UTIL_SH
