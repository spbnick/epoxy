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

. bt_util.sh
. bt_test.sh

# Verify BT_PROTOCOL value
if [ -n "${BT_PROTOCOL:-}" ] &&
   [ "$BT_PROTOCOL" != false ] && [ "$BT_PROTOCOL" != true ]; then
    echo "Invalid value of BT_PROTOCOL environment variable:" \
         "\"$BT_PROTOCOL\", expecting \"true\", \"false\", or nothing" >&2
    exit 127
fi

if [ $BASH_SUBSHELL == "${_BT_SUBSHELL:-}" ]; then
    bt_abort "Re-initializing test in the same (sub)shell"
fi

# Subshell depth of the last initialized test
declare _BT_SUBSHELL=$BASH_SUBSHELL

# Use test protocol for this test, if true
declare _BT_PROTOCOL="${BT_PROTOCOL:-false}"

# Test name stack
declare -x _BT_NAME_STACK="${_BT_NAME_STACK:-}"

# Passed subtest counter
declare -i _BT_PASSED_COUNT=0
# Waived subtest counter
declare -i _BT_WAIVED_COUNT=0
# Failed subtest counter
declare -i _BT_FAILED_COUNT=0
# Paniced subtest counter
declare -i _BT_PANICED_COUNT=0

# Teardown command argv array
declare -a _BT_TEARDOWN=()

# If wasn't included in the same shell yet
if [ -z ${_BT_SH+set} ]; then
declare -r _BT_SH=

# Exit this test with PASSED status.
# The final result will still depend on subtest status.
function bt_pass()
{
    exit 0
}

# Exit this test with FAILED status.
function bt_fail()
{
    exit 1
}

# Exit the test immediately with PANICED status, skipping teardown,
# causing all the super-tests to panic also.
function bt_panic()
{
    trap - EXIT
    _bt_conclude $BT_TEST_STATUS_PANICED
}

# Log current test status
# Args: status
function _bt_log_status()
{
    declare -r status="$1"
    bt_assert bt_test_status_is_valid \$status
    declare -r name="$_BT_NAME_STACK"
    echo "${name:+$name }`bt_test_status_to_str $status`" >&2
}

# Register subtest status
# Args: status
function _bt_register_status()
{
    declare -r status="$1"
    bt_assert bt_test_status_is_valid \$status
    declare -r count_var="_BT_`bt_test_status_to_str $status`_COUNT"
    eval "$count_var=$count_var+1"
}

# Conclude this test with a status, according to protocol: log status if
# necessary and exit with appropriate exit status.
# Args: status
function _bt_conclude()
{
    declare -r status="$1"

    if $_BT_PROTOCOL; then
        exit $status
    else
        _bt_log_status $status
        [ $status -le $BT_TEST_STATUS_WAIVED ] && exit 0 || exit 1
    fi
}

# Evaluate and execute a general subtest command expression.
#
# Args: [option...] [--] subtest_name [eval_arg...]
#
# Options:
#   -s, --status=STATUS Expect STATUS exit status/pipestatus. Default is 0.
#   -w, --waived        Don't evaluate, report and count subtest as WAIVED.
#
function bt_eval()
{
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
                    bt_abort "Invalid -s/--status option value"
                fi
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                bt_abort "Unknown option: $1"
                ;;
        esac
    done

    if [ $# == 0 ]; then
        bt_abort "Invalid number of positional arguments"
    fi
    declare -r _name="$1"
    shift

    # "Enter" the test
    bt_strstack_push _BT_NAME_STACK / "$_name"

    if $_waived; then
        _status=$BT_TEST_STATUS_WAIVED
    else
        if eval "$@; _status=\"\${PIPESTATUS[*]}\"";
           bt_pipestatus_eq "$_status" "$_expected_status"; then
            _status=$BT_TEST_STATUS_PASSED
        else
            _status=$BT_TEST_STATUS_FAILED
        fi
    fi

    _bt_log_status $_status
    # "Exit" the test
    bt_strstack_pop _BT_NAME_STACK /
    _bt_register_status $_status
}

# Setup a test protocol-conforming subtest execution.
#
# Args: [option...] [--] subtest_name
#
# Options:
#   -w, --waived        Don't run the test, report and count it as WAIVED.
#
function bt_subtest_begin()
{
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
                bt_abort "Unknown option: $1"
                ;;
        esac
    done

    if [ $# != 1 ]; then
        bt_abort "Invalid number of positional arguments"
    fi

    declare -r name="$1"

    # "Enter" the test
    bt_strstack_push _BT_NAME_STACK / "$name"
    # Export "waived" flag, so if subtest is waived it could exit immediately
    export _BT_WAIVED="$waived"
    # Disable errexit so a "failed" subtest doesn't terminate this one
    bt_attrs_push +o errexit
}

# Conclude a subtest execution.
function bt_subtest_end()
{
    # Grab the last status, first thing
    declare status=$?
    # Restore errexit state
    bt_attrs_pop
    # Reset "waived" flag, so it doesn't affect anything else
    unset _BT_WAIVED

    if ! bt_test_status_is_valid $status; then
        echo "Invalid $_BT_NAME_STACK" \
             "test protocol exit status: $status" >&2
        status=$BT_TEST_STATUS_FAILED
    fi

    _bt_log_status $status
    # "Exit" the test
    bt_strstack_pop _BT_NAME_STACK /
    _bt_register_status $status
    if [ $status == $BT_TEST_STATUS_PANICED ]; then
        bt_panic
    fi
}

# Execute a test protocol-conforming subtest command.
#
# Args: [option...] [--] subtest_name subtest_executable [subtest_arg...]
#
# Options:
#   -w, --waived        Don't run the test, report and count it as WAIVED.
#
function bt_subtest()
{
    declare -a opts=()
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +w \
                         --longoptions waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -w|--waived)    bt_arrstack_push opts "$1"; shift;;
            --)             shift; break;;
            *)              bt_abort "Unknown option: $1";;
        esac
    done

    if [ $# -lt 2 ]; then
        bt_abort "Invalid number of positional arguments"
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

# Set teardown command
# Args: ...
function bt_set_teardown()
{
    _BT_TEARDOWN=("$@")
}

# Assign positional parameters to a list of variables.
# Args: [variable_name...] [-- [parameter_value...]]
function _bt_read_args()
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

# Handle test EXIT trap
function _bt_exit_trap()
{
    # Grab the last status, first thing
    declare status="$?"

    # If teardown fails
    if [ ${_BT_TEARDOWN+set} ] && ! "${_BT_TEARDOWN[@]}"; then
        status=$BT_TEST_STATUS_PANICED
    # else, if exiting with failure or there were failed tests
    elif [ $status != 0 ] || [ $_BT_FAILED_COUNT != 0 ]; then
        status=$BT_TEST_STATUS_FAILED
    # else, if there were waived tests
    elif [ $_BT_WAIVED_COUNT != 0 ]; then
        status=$BT_TEST_STATUS_WAIVED
    else
        status=$BT_TEST_STATUS_PASSED
    fi

    _bt_conclude $status
}

fi # _BT_SH

# If entering a waived test
if ${_BT_WAIVED:-false}; then
    _bt_conclude $BT_TEST_STATUS_WAIVED
fi

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    echo Enhanced getopt not found >&2
    exit 1
fi

# Set EXIT trap as soon as possible to capture any internal errors
trap _bt_exit_trap EXIT

# Ask all subtests to use test protocol.
# Exporting to all subprocesses unconditionally to prevent ignoring waived
# state if a subtest is accidentally invoked with bt_eval, instead of
# bt_subtest.
export BT_PROTOCOL=true

# Parse test command line arguments
_bt_read_args "$@"
