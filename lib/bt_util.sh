#
# Utilities library
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
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

# Abort execution by sending SIGABRT to $BASHPID, optionally outputting a
# message.
# Args: [message...]
function bt_abort()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    kill -s SIGABRT $BASHPID
}

# Abort execution if an assertion is invalid (a command fails).
# Args: [command [arg...]]
function bt_abort_assert()
{
    declare _status=
    bt_attrs_push +o errexit
    (
        bt_attrs_pop
        "$@"
    )
    _status=$?
    bt_attrs_pop
    if [ $_status != 0 ]; then
        bt_abort "Assertion failed: $@"
    fi
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
    # Using process substitution instead of command substitution,
    # because the latter resets errexit.
    declare opts
    if read -rd '' opts < <(set +o); [ $? != 1 ]; then
        bt_abort Failed to read attrs
    fi
    bt_arrstack_push _BT_ATTR_STACK "$opts"
    if [ $# != 0 ]; then
        set "$@"
    fi
}

# Pop shell attribute state from the state stack.
function bt_attrs_pop()
{
    eval "`bt_arrstack_peek _BT_ATTR_STACK`"
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

# Assign positional parameters to a list of variables.
# Args: [variable_name...] [-- [parameter_value...]]
function bt_read_args()
{
    # NOTE: Locals are prepended with underscore to prevent clashes with
    #       parameter names
    declare _a
    declare -a _names=()
    declare -i _i

    _i=0
    while (( $# > 0 )); do
        _a="$1"
        shift
        if [ "$_a" == "--" ]; then
            break;
        fi
        _names[_i]="$_a"
        _i=_i+1
    done

    _i=0
    while (( $# > 0 && _i < ${#_names[@]} )); do
        eval "${_names[_i]}=\"$1\""
        shift
        _i=_i+1
    done

    if (( $# > 0 || _i < ${#_names[@]} )); then
        echo "Invalid number of arguments" >&2
        echo -n "Usage: `basename \"$0\"`" >&2
        for (( _i = 0; _i < ${#_names[@]}; _i++ )); do
            echo -n " <${_names[_i]}>"
        done
        echo >&2
        return 1
    fi
}

# Check if a boolean value is valid
# Args: value
function bt_bool_is_valid()
{
    bt_abort_assert [ ${1+set} ]
    [ "$1" == "true" ] || [ "$1" == "false" ]
}

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    bt_abort_assert Enhanced getopt not found
fi

fi # _BT_UTIL_SH
