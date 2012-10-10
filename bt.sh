# Bash test framework
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

# Exit immediately, if a simple command exits with non-zero status
set -o errexit
# Pipe status is the status of the rightmost unsuccessful command
set -o pipefail
# Abort if expanding an unset variable
set -o nounset
# Enable extended debugging.
# Needed for DEBUG trap propagation and BASH_ARGV/BASH_ARGC.
shopt -s extdebug

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    echo Enhanced getopt not found >&2
    exit 1
fi

# Test protocol status values
declare -i _BT_STATUS_PASSED=1 \
           _BT_STATUS_WAIVED=2 \
           _BT_STATUS_FAILED=3

# Use test exit status protocol for this test, if true
declare _BT_STATUS_PROTOCOL="${BT_STATUS_PROTOCOL:-false}"
if [ "$_BT_STATUS_PROTOCOL" != "true" ] &&
   [ "$_BT_STATUS_PROTOCOL" != "false" ]; then
    echo "Invalid value of BT_STATUS_PROTOCOL environment variable:" \
         "\"$BT_STATUS_PROTOCOL\", expecting \"true\" or \"false\"." >&2
    exit 1
fi

# Ask all subtests to use test exit status protocol.
# Exporting to all subprocesses unconditionally to prevent ignoring waived
# state if a subtest is accidentally invoked with bt_eval, instead of
# bt_subtest.
export BT_STATUS_PROTOCOL=true

# If entering a waived test
if ${_BT_WAIVED:-false}; then
    # If asked for test protocol exit status
    if $_BT_STATUS_PROTOCOL; then
        exit $_BT_STATUS_WAIVED
    else 
        exit 0
    fi
fi

# Test name stack
declare -x _BT_NAME_STACK="${_BT_NAME_STACK:-}"

# Test passed subtest counter
declare -i _BT_PASSED_COUNT=0
# Test failed subtest counter
declare -i _BT_FAILED_COUNT=0
# Test waived subtest counter
declare -i _BT_WAIVED_COUNT=0

# Shell attribute state stack
declare -a _BT_ATTR_STACK=()

# Handle test EXIT trap
function _bt_exit_trap() {
    # Grab the last status, first thing
    declare status="$?"

    if [[ $status != 0 || $_BT_FAILED_COUNT != 0 ]]; then
        status=3
    elif [ $_BT_WAIVED_COUNT != 0 ]; then
        status=2
    else
        status=1
    fi

    if $_BT_STATUS_PROTOCOL; then
        exit $status
    elif [ $status -le 2 ]; then
        exit 0
    else
        exit 1
    fi

}

# Set EXIT trap as soon as possible to capture any internal errors
trap _bt_exit_trap EXIT

# Output a backtrace
# Args: [start_frame]
function bt_backtrace() {
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

# Push values to an array-based stack.
# Args: stack value...
function bt_arrstack_push() {
    declare -r _stack="$1"
    shift
    while (( $# > 0 )); do
        eval "$_stack[\${#$_stack[@]}]=\"\$1\""
        shift
    done
}

# Get a value from the top of an array-based stack.
# Args: stack
function bt_arrstack_peek() {
    declare -r _stack="$1"
    if eval "test \${#$_stack[@]} -eq 0"; then
        echo "Not enough values in an array-based stack" >&2
        exit 1
    fi
    eval "echo \"\${$_stack[\${#$_stack[@]}-1]}\""
}

# Pop values from an array-based stack.
# Args: stack [num_values]
function bt_arrstack_pop() {
    declare -r _stack="$1"
    declare _num_values="${2:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        echo "Invalid number of values: $_num_values"
        exit 1
    fi

    while (( _num_values > 0 )); do
        if eval "test \${#$_stack[@]} -eq 0"; then
            echo "Not enough values in an array-based stack" >&2
            exit 1
        fi
        eval "unset $_stack[\${#$_stack[@]}-1]"
        _num_values=$((_num_values-1))
    done
}

# Push values to a string-based stack.
# Args: stack value...
function bt_strstack_push() {
    declare -r _stack="$1"
    shift
    while (( $# > 0 )); do
        if [[ "$1" == *[/[:cntrl:]]* ]]; then
            echo "Invalid string-based stack value" >&2
            exit 1
        fi
        eval "$_stack=\"\$$_stack/$1\"";
        shift
    done
}

# Get a value from the top of a string-based stack.
# Args: stack
function bt_strstack_peek() {
    declare -r _stack="$1"
    if eval "test -z \"\$$_stack\""; then
        echo "Not enough values in a string-based stack" >&2
        exit 1
    fi
    eval "echo \"\${$_stack##*/}\""
}

# Pop values from a string-based stack.
# Args: stack [num_values]
function bt_strstack_pop() {
    declare -r _stack="$1"
    declare _num_values="${2:-1}"

    if [[ "$_num_values" == *[^0-9]* ]]; then
        echo "Invalid number of values: $_num_values" >&2
        exit 1
    fi

    while (( _num_values > 0 )); do
        if eval "test -z \"\$$_stack\""; then
            echo "Not enough values in a string-based stack" >&2
            exit 1
        fi
        eval "$_stack=\"\${$_stack%/*}\""
        _num_values=$((_num_values-1))
    done
}

# Push shell attribute state to the state stack, optionally invoke "set".
# Args: [set_arg...]
function bt_attrs_push() {
    bt_arrstack_push _BT_ATTR_STACK "`set +o`"
    if [ $# != 0 ]; then
        set "$@"
    fi
}

# Pop shell attribute state from the state stack.
function bt_attrs_pop() {
    eval "`bt_arrstack_peek _BT_ATTR_STACK`"
    bt_arrstack_pop _BT_ATTR_STACK
}

# Convert pipestatus array elements to a single status code.
# Args: [status...]
function bt_pipestatus_to_status() {
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
function bt_pipestatus_eq() {
    if [[ "$1" == *" "* ]]; then
        [[ "$2" == *" "* && "$1" == "$2" ||
           `bt_pipestatus_to_status $1` == "$2" ]]
    else
        [[ "$2" == *" "* && "$1" == `bt_pipestatus_to_status $2` ||
           "$1" == "$2" ]]
    fi
}

# Register current subtest as passed.
function _bt_register_passed() {
    _BT_PASSED_COUNT=_BT_PASSED_COUNT+1
    echo "$_BT_NAME_STACK PASSED"
}

# Register current subtest as waived
function _bt_register_waived() {
    _BT_WAIVED_COUNT=_BT_WAIVED_COUNT+1
    echo "$_BT_NAME_STACK WAIVED"
}

# Register current subtest as failed
function _bt_register_failed() {
    _BT_FAILED_COUNT=_BT_FAILED_COUNT+1
    echo "$_BT_NAME_STACK FAILED"
}

# Evaluate and execute a general subtest command expression.
#
# Args: [option...] [--] subtest_name [eval_arg...]
#
# Options:
#   -s, --status=STATUS Expect STATUS exit status/pipestatus. Default is 0.
#   -w, --waived        Don't evaluate, report and count subtest as WAIVED.
#
function bt_eval() {
    # NOTE: Locals are prepended with underscore to prevent clashes with
    #       variables referenced in supplied eval arguments.
    declare _waived=false
    declare _expected_status=0
    declare _args=`getopt --name ${FUNCNAME[0]} \
                          --options +s:w \
                          --longoptions status:,waived \
                          -- "$@"`
    declare _status
    eval set -- "$_args"

    while true; do
        case "$1" in
            -w|--waived)
                _waived=true
                shift
                ;;
            -s|--status)
                _expected_status="$2";
                if [[ "$_expected_status" == "" ||
                      "$_expected_status" == *[^" "0-9]* ]]; then
                    echo "Invalid -s/--status option value" >&2
                    exit 1
                fi
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ $# == 0 ]; then
        echo "Invalid number of positional arguments" >&2
        exit 1
    fi
    declare -r _name="$1"
    shift

    # "Enter" the test
    bt_strstack_push _BT_NAME_STACK "$_name"

    if $_waived; then
        _bt_register_waived
    else
        if eval "$@; _status=\"\${PIPESTATUS[*]}\"";
           bt_pipestatus_eq "$_status" "$_expected_status"; then
            _bt_register_passed
        else
            _bt_register_failed
        fi
    fi

    # "Exit" the test
    bt_strstack_pop _BT_NAME_STACK
}

# Setup a test protocol-conforming subtest execution.
#
# Args: [option...] [--] subtest_name
#
# Options:
#   -w, --waived        Don't run the test, report and count it as WAIVED.
#
function bt_subtest_begin() {
    declare waived=false
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +w \
                         --longoptions waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -w|--waived)
                waived=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ $# != 1 ]; then
        echo "Invalid number of positional arguments" >&2
        exit 1
    fi

    declare -r name="$1"

    # "Enter" the test
    bt_strstack_push _BT_NAME_STACK "$name"
    # Export "waived" flag, so if subtest is waived it could exit immediately
    export _BT_WAIVED="$waived"
    # Disable errexit so a "failed" subtest doesn't terminate this one
    bt_attrs_push +o errexit
}

# Conclude a subtest execution.
function bt_subtest_end() {
    # Grab the last status, first thing
    declare status=$?
    # Restore errexit state
    bt_attrs_pop
    # Reset "waived" flag, so it doesn't affect anything else
    unset _BT_WAIVED

    case $status in
        $_BT_STATUS_PASSED)
            _bt_register_passed
            ;;
        $_BT_STATUS_WAIVED)
            _bt_register_waived
            ;;
        *)
            if [ $status != $_BT_STATUS_FAILED ]; then
                echo "Invalid $_BT_NAME_STACK" \
                     "test protocol exit status: $status" >&2
            fi
            _bt_register_failed
            ;;
    esac

    # "Exit" the test
    bt_strstack_pop _BT_NAME_STACK
}

# Execute a test protocol-conforming subtest command.
#
# Args: [option...] [--] subtest_name subtest_executable [subtest_arg...]
#
# Options:
#   -w, --waived        Don't run the test, report and count it as WAIVED.
#
function bt_subtest() {
    declare -a opts=()
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +w \
                         --longoptions waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -w|--waived)
                bt_arrstack_push opts "$1"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ $# -lt 2 ]; then
        echo "Invalid number of positional arguments" >&2
        exit 1
    fi
    declare -r name="$1"
    shift

    if [ ${#opts[@]} == 0 ]; then
        bt_subtest_begin -- "$name"
    else
        bt_subtest_begin "${opts[@]}" -- "$name"
    fi
    "$@"
    bt_subtest_end
}

# Assign positional parameters to a list of variables.
# Args: [variable_name...] [-- [parameter_value...]]
function _bt_read_args() {
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

_bt_read_args "$@"
