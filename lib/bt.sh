#
# Test library
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_SH+set} ]; then
declare -r _BT_SH=

. bt_util.sh
. bt_status.sh

# Protocol for this test ("generic", or "test")
declare _BT_PROTOCOL
# Protocol for sub-tests (nothing, "generic", or "test")
declare -x BT_PROTOCOL

# Assert name stack
declare -x _BT_NAME_STACK

# Passed assert counter
declare -i _BT_COUNT_PASSED
# Waived assert counter
declare -i _BT_COUNT_WAIVED
# Failed assert counter
declare -i _BT_COUNT_FAILED
# Errored assert counter
declare -i _BT_COUNT_ERRORED
# Panicked assert counter
declare -i _BT_COUNT_PANICKED
# Aborted assert counter
declare -i _BT_COUNT_ABORTED

# Teardown command argc array
declare -a _BT_TEARDOWN_ARGC
# Teardown command argv array
declare -a _BT_TEARDOWN_ARGV

# Initialize the test.
function _bt_init()
{
    # Verify BT_PROTOCOL value
    if [ -n "${BT_PROTOCOL:-}" ] &&
       [ "$BT_PROTOCOL" != "generic" ] && [ "$BT_PROTOCOL" != "test" ]; then
        echo "Invalid value of BT_PROTOCOL environment variable:" \
             "\"$BT_PROTOCOL\","
             "expecting \"test\", \"generic\", or nothing" >&2
        exit 127
    fi

    _BT_PROTOCOL="${BT_PROTOCOL:-generic}"
    _BT_NAME_STACK="${_BT_NAME_STACK:-}"
    _BT_COUNT_PASSED=0
    _BT_COUNT_WAIVED=0
    _BT_COUNT_FAILED=0
    _BT_COUNT_ERRORED=0
    _BT_COUNT_PANICKED=0
    _BT_COUNT_ABORTED=0
    _BT_TEARDOWN_ARGC=()
    _BT_TEARDOWN_ARGV=()

    # Set EXIT trap as soon as possible to capture any internal errors
    trap _bt_trap_exit EXIT

    # Set SIGABRT trap to capture aborts
    trap _bt_trap_sigabrt SIGABRT

    # Ask all subtests to use the test protocol.
    # Exporting to all subprocesses unconditionally to prevent ignoring waived
    # state if a subtest is accidentally invoked with bt_assert, instead of
    # bt.
    BT_PROTOCOL=test
}

# Finalize the test.
# Args: status
function _bt_fini()
{
    declare -r status="$1"
    bt_abort_assert bt_status_is_valid "$status"

    trap - EXIT

    if [ $_BT_PROTOCOL == test ]; then
        exit "$status"
    else
        _bt_log_status "$_BT_NAME_STACK" $status
        [ "$status" -le $BT_STATUS_WAIVED ]
        exit
    fi
}

# Exit the test immediately with PANICKED status, skipping (the rest of)
# teardown, optionally outputting a message to stderr.
# Args: [message...]
function bt_panic()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    _bt_fini $BT_STATUS_PANICKED
}

# Exit the test with ERRORED status, optionally outputting a message to
# stderr.
# Args: [message...]
function bt_error()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    exit 1
}

# Log current test status
# Args: name status
function _bt_log_status()
{
    declare -r name="$1"
    declare -r status="$2"
    bt_abort_assert bt_status_is_valid "$status"
    echo "${name:+$name }`bt_status_to_str $status`" >&2
}

# Register test status
# Args: status
function _bt_register_status()
{
    declare -r status="$1"
    bt_abort_assert bt_status_is_valid "$status"
    declare -r status_str=`bt_status_to_str $status`
    declare -r count_var="_BT_COUNT_$status_str"
    eval "$count_var=$count_var+1"
}

# Setup a command assertion.
#
# Args: [option...] [--] name
#
# Options:
#   -w, --waived        Waive the assertion.
#   -s, --status=STATUS Expect STATUS exit status. Default is 0.
#
function bt_assert_begin()
{
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +s:w \
                         --longoptions status:,waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -w|--waived)
                waived=true
                shift
                ;;
            -s|--status)
                expected_status="$2";
                if [[ "$expected_status" == "" ||
                      "$expected_status" == *[^" "0-9]* ]]; then
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
    declare -r name="$1"
    shift

    # Remember expected status - to be compared to the command exit status
    declare -g _BT_EXPECTED_STATUS="$expected_status"

    # Export "waived" flag, so if the command is waived it could exit
    # immediately
    declare -g -x _BT_WAIVED="$waived"

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"
    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a command assertion.
function bt_assert_end()
{
    # Grab the last status, first thing
    declare status=$?
    declare name="$_BT_NAME_STACK"
    # Restore errexit state
    bt_attrs_pop
    # "Exit" the assertion
    bt_strstack_pop _BT_NAME_STACK /

    bt_abort_assert [ ${_BT_EXPECTED_STATUS+set} ]
    if [ $status == "$_BT_EXPECTED_STATUS" ]; then
        status=$BT_STATUS_PASSED
    else
        status=$BT_STATUS_FAILED
    fi
    unset _BT_EXPECTED_STATUS

    bt_abort_assert [ ${_BT_WAIVED+set} ]
    if $_BT_WAIVED; then
        status=$BT_STATUS_WAIVED
    fi
    unset _BT_WAIVED

    bt_abort_assert bt_status_is_valid $status
    _bt_log_status "$name" $status
    _bt_register_status $status
    if [ $status -ge $BT_STATUS_PANICKED ]; then
        _bt_fini $status
    fi
}

# Assert a command.
#
# Args: [option...] [--] name [command [arg...]]
#
# Options:
#   -w, --waived        Waive the assertion.
#   -s, --status=STATUS Expect STATUS exit status. Default is 0.
#
function bt_assert()
{
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +s:w \
                         --longoptions status:,waived \
                         -- "$@"`
    declare -a begin_args=()
    eval set -- "$args"

    while true; do
        case "$1" in
            -w|--waived)
                waived=true
                shift
                ;;
            -s|--status)
                expected_status="$2";
                if [[ "$expected_status" == "" ||
                      "$expected_status" == *[^" "0-9]* ]]; then
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
    declare -r name="$1"
    shift

    if $waived; then
        begin_args[${#begin_args[@]}]="--waived"
    fi

    if [ "$expected_status" != 0 ]; then
        begin_args[${#begin_args[@]}]="--status"
        begin_args[${#begin_args[@]}]="$expected_status"
    fi

    begin_args[${#begin_args[@]}]="--"
    begin_args[${#begin_args[@]}]="$name"

    bt_assert_begin "${begin_args[@]}"
    if ! $waived; then
        "$@"
    fi
    bt_assert_end
}

# Setup a test assertion.
#
# Args: [option...] [--] name
#
# Options:
#   -w, --waived        Waive the assertion.
#
function bt_begin()
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
    shift

    # Export "waived" flag, so if the command is waived it could exit
    # immediately
    declare -g -x _BT_WAIVED="$waived"

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"

    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a test assertion.
function bt_end()
{
    # Grab the last status, first thing
    declare status=$?
    declare name="$_BT_NAME_STACK"
    # Restore errexit state
    bt_attrs_pop
    # "Exit" the assertion
    bt_strstack_pop _BT_NAME_STACK /

    bt_abort_assert [ ${_BT_WAIVED+set} ]
    if $_BT_WAIVED; then
        status=$BT_STATUS_WAIVED
    fi
    unset _BT_WAIVED

    bt_abort_assert bt_status_is_valid $status
    _bt_log_status "$name" $status
    _bt_register_status $status
    if [ $status -ge $BT_STATUS_PANICKED ]; then
        _bt_fini $status
    fi
}

# Assert a test.
#
# Args: [option...] [--] name [command [arg...]]
#
# Options:
#   -w, --waived        Waive the assertion.
#
function bt()
{
    declare waived=false
    declare -a opts=()
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +w \
                         --longoptions waived \
                         -- "$@"`
    declare -a begin_args=()
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

    if [ $# == 0 ]; then
        bt_abort "Invalid number of positional arguments"
    fi
    declare -r name="$1"
    shift

    if $waived; then
        begin_args[${#begin_args[@]}]="--waived"
    fi

    begin_args[${#begin_args[@]}]="--"
    begin_args[${#begin_args[@]}]="$name"

    bt_begin "${begin_args[@]}"
    if [ $# != 0 ]; then
        "$@"
    else
        (
            . bt_init.sh
        )
    fi
    bt_end
}

# Push a command to the teardown command stack.
# Args: ...
function bt_teardown_push()
{
    bt_arrstack_push _BT_TEARDOWN_ARGC $#
    bt_arrstack_push _BT_TEARDOWN_ARGV "$@"
}

# Pop commands from the teardown command stack.
# Args: [num_commands]
function bt_teardown_pop()
{
    declare num_commands="${1:-1}"
    bt_abort_assert [ "$num_commands" -le ${#_BT_TEARDOWN_ARGC[@]} ]
    for ((; num_commands > 0; num_commands--)); do
        bt_arrstack_pop _BT_TEARDOWN_ARGV \
                        `bt_arrstack_peek _BT_TEARDOWN_ARGC`
        bt_arrstack_pop _BT_TEARDOWN_ARGC
    done
}

# Execute a teardown command from the top of the teardown stack.
function bt_teardown_exec()
{
    bt_abort_assert [ ${#_BT_TEARDOWN_ARGC[@]} != 0 ]
    "${_BT_TEARDOWN_ARGV[@]: -${_BT_TEARDOWN_ARGC[-1]}}"
}

# Execute and pop all teardown commands from the teardown stack.
function _bt_teardown()
{
    while [ ${#_BT_TEARDOWN_ARGC[@]} != 0 ]; do
        bt_teardown_exec
        bt_teardown_pop
    done
}

# Handle EXIT trap
function _bt_trap_exit()
{
    # Grab the last status, first thing
    declare status="$?"
    declare teardown_status=

    # Execute teardown in a subshell
    bt_attrs_push +o errexit
    (
        bt_attrs_pop
        _bt_teardown
    )
    teardown_status=$?
    bt_attrs_pop

    # If teardown failed
    if [ $teardown_status != 0 ]; then
        status=$BT_STATUS_PANICKED
    # else, if exiting with failure
    elif [ $status != 0 ]; then
        status=$BT_STATUS_ERRORED
    # else, if there were failed tests
    elif [ $_BT_COUNT_FAILED != 0 ]; then
        status=$BT_STATUS_FAILED
    # else, if there were waived tests
    elif [ $_BT_COUNT_WAIVED != 0 ]; then
        status=$BT_STATUS_WAIVED
    else
        status=$BT_STATUS_PASSED
    fi

    _bt_fini $status
}

# Handle SIGABRT
function _bt_trap_sigabrt()
{
    trap - SIGABRT
    bt_backtrace 1 >&2
    _bt_fini $BT_STATUS_ABORTED
}

fi # _BT_SH
