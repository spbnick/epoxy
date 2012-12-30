#
# Test suite
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
. bt_glob.sh

# Protocol for this suite ("generic", or "suite")
declare _BT_PROTOCOL
# Protocol for sub-suites (nothing, "generic", or "suite")
declare -x BT_PROTOCOL

# Assertion name stack
declare -x _BT_NAME_STACK

# Skipped assertion counter
declare _BT_COUNT_SKIPPED
# Passed assertion counter
declare _BT_COUNT_PASSED
# Waived assertion counter
declare _BT_COUNT_WAIVED
# Failed assertion counter
declare _BT_COUNT_FAILED
# Errored assertion counter
declare _BT_COUNT_ERRORED
# Panicked assertion counter
declare _BT_COUNT_PANICKED
# Aborted assertion counter
declare _BT_COUNT_ABORTED

# NOTE: using export instead of declare -x as a bash 3.x bug workaround
# Glob pattern matching assertions to (not) include in the run
export BT_INCLUDE BT_DONT_INCLUDE
# Glob pattern matching assertions to (not) remove skipped status from
export BT_UNSKIP BT_DONT_UNSKIP
# Glob pattern matching assertions to (not) remove waived status from
export BT_UNWAIVE BT_DONT_UNWAIVE

# Teardown command argc array
declare -a _BT_TEARDOWN_ARGC
# Teardown command argv array
declare -a _BT_TEARDOWN_ARGV

# Initialize the test suite.
function _bt_init()
{
    # Verify BT_PROTOCOL value
    if [ -n "${BT_PROTOCOL:-}" ] &&
       [ "$BT_PROTOCOL" != "generic" ] && [ "$BT_PROTOCOL" != "suite" ]; then
        echo "Invalid value of BT_PROTOCOL environment variable:" \
             "\"$BT_PROTOCOL\","
             "expecting \"suite\", \"generic\", or nothing" >&2
        exit 127
    fi

    _BT_PROTOCOL="${BT_PROTOCOL:-generic}"
    _BT_NAME_STACK="${_BT_NAME_STACK:-}"
    _BT_COUNT_SKIPPED=0
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

    # Ask all sub-suites to use the suite protocol.
    # Exporting to all subprocesses unconditionally to prevent losing detailed
    # state if a sub-suite is accidentally invoked with bt_test, instead of
    # bt_suite.
    BT_PROTOCOL=suite
}

# Unset external test suite variables
function _bt_cleanup()
{
    unset BT_PROTOCOL \
          _BT_NAME_STACK \
          BT_{,DONT_}{INCLUDE,UNSKIP,UNWAIVE}
}

# Finalize the test suite.
# Args: status
function _bt_fini()
{
    declare -r status="$1"
    bt_abort_assert bt_status_is_valid "$status"

    trap - EXIT

    if [ $_BT_PROTOCOL == suite ]; then
        exit "$status"
    else
        _bt_log_status "$_BT_NAME_STACK" $status
        [ "$status" -le $BT_STATUS_WAIVED ]
        exit
    fi
}

# Match either a final or a partial assertion path against a filter - a pair
# of optional pattern variables - one that should match and one that
# shouldn't.
# Args: path final filter default
function bt_path_filter()
{
    declare -r path="$1"
    declare -r final="$2"
    declare -r filter="$3"
    declare -r default="$4"

    declare -r include_var="BT_$filter"
    declare -r exclude_var="BT_DONT_$filter"

    # If exclude variable is specified
    if [ -n "${!exclude_var+set}" ]; then
        # If excluded, i.e.:
        # If it's the exact node
        if bt_glob_aborting "${!exclude_var}" "$path" ||
           # Or a child
           bt_glob_aborting --text-prefix "${!exclude_var}/" "$path"; then
            return 1
        else
            return 0
        fi
    fi

    # If include variable is specified
    if [ -n "${!include_var+set}" ]; then
        # If included, i.e.:
        # If it's a possible parent
        if ! $final &&
           bt_glob_aborting --pattern-prefix "${!include_var}" "$path/" ||
           # Or the exact node
           bt_glob_aborting "${!include_var}" "$path" ||
           # Or a child
           bt_glob_aborting --text-prefix "${!include_var}/" "$path"; then
            return 0
        else
            return 1
        fi
    fi

    if $default; then
        return 0
    else
        return 1
    fi
}

# Exit the suite immediately with PANICKED status, skipping (the rest of)
# teardown, optionally outputting a message to stderr.
# Args: [message...]
function bt_panic()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    _bt_fini $BT_STATUS_PANICKED
}

# Exit the suite with ERRORED status, optionally outputting a message to
# stderr.
# Args: [message...]
function bt_error()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    exit 1
}

# Log an assertion status.
# Args: name status
function _bt_log_status()
{
    declare -r name="$1"
    declare -r status="$2"
    echo "${name:+$name }`bt_status_to_str \"\$status\"`"
}

# Register an assertion status.
# Args: status
function _bt_register_status()
{
    declare -r status="$1"
    declare -r status_str=`bt_status_to_str "\$status"`
    declare -r count_var="_BT_COUNT_$status_str"
    eval "$count_var=$((count_var+1))"
}

# Setup a test execution.
#
# Args: [option...] [--] name
#
# Options:
#   -s, --skipped                   Mark assertion as skipped.
#   -w, --waived                    Mark assertion as waived.
#   -e, --expected-status=STATUS    Expect STATUS exit status. Default is 0.
#
function bt_test_begin()
{
    declare skipped=false
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +swe: \
                         --longoptions skipped,waived,expected-status: \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -s|--skipped)
                skipped=true
                shift
                ;;
            -w|--waived)
                waived=true
                shift
                ;;
            -e|--expected-status)
                expected_status="$2";
                if [[ "$expected_status" == "" ||
                      "$expected_status" == *[^" "0-9]* ]]; then
                    bt_abort "Invalid -e/--expected-status option value: $2"
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

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"

    # Disable skipping if the path matches "UNSKIP" filter
    if bt_path_filter "$_BT_NAME_STACK" true UNSKIP false; then
        skipped=false
    fi

    # Enable skipping if the path doesn't match "INCLUDE" filter
    if ! bt_path_filter "$_BT_NAME_STACK" true INCLUDE true; then
        skipped=true
    fi

    # Disable waiving if the path matches "UNWAIVE" filter
    if bt_path_filter "$_BT_NAME_STACK" true UNWAIVE false; then
        waived=false
    fi

    # Export "skipped" flag, so if the command is skipped it could exit
    # immediately
    export _BT_SKIPPED="$skipped"

    # Export "waived" flag, so if the command is waived it could exit
    # immediately
    export _BT_WAIVED="$waived"

    # Remember expected status - to be compared to the command exit status
    _BT_EXPECTED_STATUS="$expected_status"

    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a test execution.
function bt_test_end()
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

    bt_abort_assert [ ${_BT_SKIPPED+set} ]
    if $_BT_SKIPPED; then
        status=$BT_STATUS_SKIPPED
    fi
    unset _BT_SKIPPED

    bt_abort_assert bt_status_is_valid $status
    _bt_log_status "$name" $status
    _bt_register_status $status
    if [ $status -ge $BT_STATUS_PANICKED ]; then
        _bt_fini $status
    fi
}

# Execute a test.
#
# Args: [option...] [--] name [command [arg...]]
#
# Options:
#   -s, --skipped                   Mark assertion as skipped.
#   -w, --waived                    Mark assertion as waived.
#   -e, --expected-status=STATUS    Expect STATUS exit status. Default is 0.
#
function bt_test()
{
    declare skipped=false
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +swe: \
                         --longoptions skipped,waived,expected-status: \
                         -- "$@"`
    declare -a begin_args=()
    eval set -- "$args"

    while true; do
        case "$1" in
            -s|--skipped)
                skipped=true
                shift
                ;;
            -w|--waived)
                waived=true
                shift
                ;;
            -e|--expected-status)
                expected_status="$2";
                if [[ "$expected_status" == "" ||
                      "$expected_status" == *[^" "0-9]* ]]; then
                    bt_abort "Invalid -e/--expected-status option value: $2"
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

    if $skipped; then
        begin_args[${#begin_args[@]}]="--skipped"
    fi

    if $waived; then
        begin_args[${#begin_args[@]}]="--waived"
    fi

    if [ "$expected_status" != 0 ]; then
        begin_args[${#begin_args[@]}]="--expected-status"
        begin_args[${#begin_args[@]}]="$expected_status"
    fi

    begin_args[${#begin_args[@]}]="--"
    begin_args[${#begin_args[@]}]="$name"

    bt_test_begin "${begin_args[@]}"
    if ! $waived && ! $skipped; then
        "$@"
    fi
    bt_test_end
}

# Setup a suite execution.
#
# Args: [option...] [--] name
#
# Options:
#   -s, --skipped                   Mark assertion as skipped.
#   -w, --waived                    Mark assertion as waived.
#
function bt_suite_begin()
{
    declare skipped=false
    declare waived=false
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +sw \
                         --longoptions skipped,waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -s|--skipped)
                skipped=true
                shift
                ;;
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

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"

    # Disable skipping if path matches "UNSKIP" filter
    if bt_path_filter "$_BT_NAME_STACK" false UNSKIP false; then
        skipped=false
    fi

    # Enable skipping if path doesn't match "INCLUDE" filter
    if ! bt_path_filter "$_BT_NAME_STACK" false INCLUDE true; then
        skipped=true
    fi

    # Disable waiving if path matches "UNWAIVE" filter
    if bt_path_filter "$_BT_NAME_STACK" false UNWAIVE false; then
        waived=false
    fi

    # Export "skipped" flag, so if the command is skipped it could exit
    # immediately
    export _BT_SKIPPED="$skipped"

    # Export "waived" flag, so if the command is waived it could exit
    # immediately
    export _BT_WAIVED="$waived"

    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a suite execution.
function bt_suite_end()
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

    bt_abort_assert [ ${_BT_SKIPPED+set} ]
    if $_BT_SKIPPED; then
        status=$BT_STATUS_SKIPPED
    fi
    unset _BT_SKIPPED

    bt_abort_assert bt_status_is_valid $status
    _bt_log_status "$name" $status
    _bt_register_status $status
    if [ $status -ge $BT_STATUS_PANICKED ]; then
        _bt_fini $status
    fi
}

# Execute a suite.
#
# Args: [option...] [--] name [command [arg...]]
#
# Options:
#   -s, --skipped                   Mark assertion as skipped.
#   -w, --waived                    Mark assertion as waived.
#
function bt_suite()
{
    declare skipped=false
    declare waived=false
    declare -a opts=()
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +sw \
                         --longoptions skipped,waived \
                         -- "$@"`
    declare -a begin_args=()
    eval set -- "$args"

    while true; do
        case "$1" in
            -s|--skipped)
                skipped=true
                shift
                ;;
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

    if $skipped; then
        begin_args[${#begin_args[@]}]="--skipped"
    fi

    if $waived; then
        begin_args[${#begin_args[@]}]="--waived"
    fi

    begin_args[${#begin_args[@]}]="--"
    begin_args[${#begin_args[@]}]="$name"

    bt_suite_begin "${begin_args[@]}"
    if [ $# != 0 ]; then
        "$@"
    else
        (
            . bt_suite_init.sh
        )
    fi
    bt_suite_end
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
    "${_BT_TEARDOWN_ARGV[@]: -${_BT_TEARDOWN_ARGC[${#_BT_TEARDOWN_ARGC[@]}-1]}}"
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
    elif [ $status != 0 ] || [ $_BT_COUNT_ERRORED != 0 ]; then
        status=$BT_STATUS_ERRORED
    # else, if there were failed assertions
    elif [ $_BT_COUNT_FAILED != 0 ]; then
        status=$BT_STATUS_FAILED
    # else, if there were waived assertions
    elif [ $_BT_COUNT_WAIVED != 0 ]; then
        status=$BT_STATUS_WAIVED
    # else, if there were passed assertions
    elif [ $_BT_COUNT_PASSED != 0 ]; then
        status=$BT_STATUS_PASSED
    # else, if there were skipped assertions
    elif [ $_BT_COUNT_SKIPPED != 0 ]; then
        status=$BT_STATUS_SKIPPED
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
