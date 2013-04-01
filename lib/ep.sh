#
# Test suite
#
# Copyright (c) 2012-2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_SH+set} ]; then
declare -r _EP_SH=

. ep_util.sh
. ep_status.sh
. ep_glob.sh
. ep_log.sh
. ep_path.sh
. ep_teardown.sh

# First FD reserved for the user
declare -r EP_USER_FD1=3
# Second FD reserved for the user
declare -r EP_USER_FD2=4

# Suite command-line arguments
declare -a EP_SUITE_ARGS=()

# List of inter-suite environment variables.
declare -a _EP_EXPORT_LIST=()

# Declare inter-suite environment variables.
# Args: [_name...]
function ep_export()
{
    ep_arrstack_push _EP_EXPORT_LIST "$@"
    export -- "$@"
}

# Protocol for suites (nothing, "generic", or "suite")
ep_export EP_PROTOCOL

# NOTE: using export instead of declare -x as a bash 3.x bug workaround
# Glob pattern matching assertions to (not) include in the run
ep_export EP_INCLUDE EP_DONT_INCLUDE
# Glob pattern matching assertions to (not) remove disabled status from
ep_export EP_ENABLE EP_DONT_ENABLE
# Glob pattern matching assertions to (not) remove waived status from
ep_export EP_CLAIM EP_DONT_CLAIM

# Assertion name stack
ep_export _EP_NAME_STACK
# "Skipped" flag - exit assertion shell immediately, if "true".
ep_export _EP_SKIPPED
# "Waived" flag - ignore assertion status, if "true".
ep_export _EP_WAIVED

# Temporary directory
ep_export EP_TMPDIR

# If "true", log setup was done
ep_export _EP_LOG_SETUP

# Last initialized subshell depth
declare _EP_SHELL_INIT_SUBSHELL

# Protocol for this suite ("generic", or "suite")
declare _EP_PROTOCOL

# If "true", the temporary directory was created by this suite
declare _EP_TMPDIR_OWNER
# If "true", the logging system was set up by this suite
declare _EP_LOG_OWNER

# Skipped assertion counter
declare _EP_COUNT_SKIPPED
# Passed assertion counter
declare _EP_COUNT_PASSED
# Waived assertion counter
declare _EP_COUNT_WAIVED
# Failed assertion counter
declare _EP_COUNT_FAILED
# Errored assertion counter
declare _EP_COUNT_ERRORED
# Panicked assertion counter
declare _EP_COUNT_PANICKED
# Aborted assertion counter
declare _EP_COUNT_ABORTED

# Initialize a (sub)shell.
function _ep_shell_init()
{
    # Exit immediately, if a simple command exits with non-zero status
    set -o errexit
    # Pipe status is the status of the rightmost unsuccessful command
    set -o pipefail
    # Abort if expanding an unset variable
    set -o nounset
    # Enable extended debugging.
    # Needed for DEBUG trap propagation and BASH_ARGV/BASH_ARGC.
    shopt -s extdebug

    if [ "$BASH_SUBSHELL" == "${_EP_SHELL_INIT_SUBSHELL:-}" ]; then
        ep_abort "Re-initializing a (sub)shell"
    fi

    # Last initialized subshell depth
    _EP_SHELL_INIT_SUBSHELL="$BASH_SUBSHELL"

    # Set PID that ep_abort should send SIGABRT to - the PID of the (sub)shell
    # being initialized, if can be retrieved
    if [ -n "${BASHPID+set}" ]; then
        EP_ABORT_PID="$BASHPID"
    elif [ -r /proc/self/stat ]; then
        declare discard
        read -r EP_ABORT_PID discard < /proc/self/stat
    fi

    ep_abort_if_not ep_bool_is_valid "${_EP_SKIPPED-false}"

    # If entering a skipped assertion shell
    if ${_EP_SKIPPED:-false}; then
        exit 0
    fi
}

# Output usage information
function _ep_usage()
{
    echo "\
Usage: `basename \"\$0\"` [OPTION]... [PATTERN]... [-- [SUITE_ARG]...]
Execute test suite.

Arguments:
    PATTERN                 Verify assertions matching PATTERN.

General options:
    -h, --help              Output this help message and exit.
    -l, --log-file=FILE     Write raw unfiltered log to FILE.

Assertion handling options:
    -i, --include=PATTERN   Verify assertions matching PATTERN.
    -e, --exclude=PATTERN,
    --dont-include=PATTERN  Don't verify assertions matching PATTERN.

    -c, --claim=PATTERN     Claim (remove \"waived\" status from) assertions
                            matching PATTERN.
    --dont-claim=PATTERN    Don't claim (don't remove \"waived\" status from)
                            assertions matching PATTERN.

    --enable=PATTERN        Enable assertions matching PATTERN.
    --dont-enable=PATTERN   Don't enable assertions matching PATTERN.

Output options:
    -f, --filter-opts=OPTS  Add OPTS to output filter (ep_log_filter) options.
    -u, --unfiltered        Don't filter output.
    -r, --raw               Don't cook (don't summarize) output.

Default options:
    --filter-opts=\"--status=PASSED\"

All patterns are Bash extended glob-like paterns.
Any arguments specified after \"--\" are passed to the suite.
"
}

# Initialize a suite shell, parse command line arguments, extracting
# framework-specific arguments and storing suite arguments in EP_SUITE_ARGS
# array.
# Args: [cmdline_arg...]
function ep_suite_init()
{
    declare args=()
    declare args_expr
    declare log_file=
    declare log_filter=true
    declare log_filter_opts="--status=PASSED"
    declare log_cook=true

    # Initialize a generic shell
    _ep_shell_init

    # Collect framework arguments
    while [ $# != 0 ]; do
        if [ "$1" == "--" ]; then
            shift;
            break;
        fi
        args[${#args[@]}]="$1"
        shift
    done

    # Store suite arguments
    EP_SUITE_ARGS=("$@")

    # If framework arguments are present
    if [ "${#args[@]}" != 0 ]; then
        # Parse framework arguments
        args_expr=`getopt --name \`basename "\$0"\` \
                          --options hl:i:e:c:f:ur \
                          --longoptions help,log-file: \
                          --longoptions include:,exclude:,dont-include: \
                          --longoptions claim:,dont-claim:,enable:,dont-enable: \
                          --longoptions filter-opts:,unfiltered,raw \
                          -- "${args[@]}"`
        eval set -- "$args_expr"

        # Read framework option arguments
        while true; do
            case "$1" in
                -h|--help)
                    _ep_usage; exit 0;;
                -l|--log-file)
                    log_file="$2";                          shift 2;;
                -i|--include)
                    ep_glob_var_or EP_INCLUDE       "$2";   shift 2;;
                -e|--exclude|--dont-include)
                    ep_glob_var_or EP_DONT_INCLUDE  "$2";   shift 2;;
                -c|--claim)
                    ep_glob_var_or EP_CLAIM         "$2";   shift 2;;
                --dont-claim)
                    ep_glob_var_or EP_DONT_CLAIM    "$2";   shift 2;;
                --enable)
                    ep_glob_var_or EP_ENABLE        "$2";   shift 2;;
                --dont-enable)
                    ep_glob_var_or EP_DONT_ENABLE   "$2";   shift 2;;
                -f|--filter-opts)
                    log_filter_opts="$log_filter_opts $2";  shift 2;;
                -u|--unfiltered)
                    log_filter=false;                       shift;;
                -r|--raw)
                    log_cook=false;                         shift;;
                --) shift; break;;
                *) ep_abort "Unknown option: $1";;
            esac
        done

        # Read framework positional arguments
        while [ $# != 0 ]; do
            if [ "$1" == "--" ]; then
                shift
                break
            fi
            ep_glob_var_or EP_INCLUDE "$1"
            shift
        done
    fi

    # Verify EP_PROTOCOL value
    if [ -n "${EP_PROTOCOL:-}" ] &&
       [ "$EP_PROTOCOL" != "generic" ] && [ "$EP_PROTOCOL" != "suite" ]; then
        echo "Invalid value of EP_PROTOCOL environment variable:" \
             "\"$EP_PROTOCOL\","
             "expecting \"suite\", \"generic\", or nothing" >&2
        exit 127
    fi

    # Initialize global variables
    _EP_PROTOCOL="${EP_PROTOCOL:-generic}"
    _EP_NAME_STACK="${_EP_NAME_STACK:-}"
    _EP_COUNT_SKIPPED=0
    _EP_COUNT_PASSED=0
    _EP_COUNT_WAIVED=0
    _EP_COUNT_FAILED=0
    _EP_COUNT_ERRORED=0
    _EP_COUNT_PANICKED=0
    _EP_COUNT_ABORTED=0

    # Clear teardown command stack
    ep_teardown_pop_all

    # Set EXIT trap as soon as possible to capture any internal errors
    trap _ep_trap_exit EXIT

    # Set SIGABRT trap to capture aborts
    trap _ep_trap_sigabrt SIGABRT

    # Ask all sub-suites to use the suite protocol.
    # Exporting to all subprocesses unconditionally to prevent losing detailed
    # state if a sub-suite is accidentally invoked with ep_test, instead of
    # ep_suite.
    EP_PROTOCOL=suite

    # Create temporary directory, if none specified
    if [ -z "${EP_TMPDIR+set}" ]; then
        EP_TMPDIR=`mktemp -d -t ep.XXXXXXXXXX`
        _EP_TMPDIR_OWNER=true
    else
        _EP_TMPDIR_OWNER=false
    fi

    # Setup logging, if not done yet
    ep_abort_if_not ep_bool_is_valid "${_EP_LOG_SETUP-false}"
    if ! ${_EP_LOG_SETUP-false}; then
        _ep_log_init "$log_file" "$log_filter" "$log_filter_opts" "$log_cook"
        _EP_LOG_SETUP=true
        _EP_LOG_OWNER=true
    else
        _EP_LOG_OWNER=false
    fi

    if [ "$_EP_PROTOCOL" == "generic" ]; then
        _ep_log_msg "STRUCT BEGIN '$_EP_NAME_STACK'"
    fi
}

# Cleanup a suite shell.
function ep_suite_cleanup()
{
    unset -- "${_EP_EXPORT_LIST[@]}"
    trap - SIGABRT
}

# Initialize a test shell.
function ep_test_init()
{
    # Initialize a generic shell
    _ep_shell_init
    # Cleanup the possible inherited suite shell
    ep_suite_cleanup
}


# Finalize the test suite.
# Args: status
function _ep_fini()
{
    declare status="$1"
    ep_abort_if_not ep_status_is_valid "$status"

    trap - EXIT

    if [ "$_EP_PROTOCOL" == "generic" ]; then
        _ep_log_msg "STRUCT END   '$_EP_NAME_STACK'" \
                    "`ep_status_to_str $status`"
    fi

    # Finish logging if this suite started it
    if ${_EP_LOG_SETUP-false} && ${_EP_LOG_OWNER-false}; then
        _ep_log_fini
        _EP_LOG_SETUP=false
        _EP_LOG_OWNER=false
    fi

    # Remove temporary directory, if created by this suite
    if $_EP_TMPDIR_OWNER; then
        rm -R "$EP_TMPDIR"
    fi

    if [ $_EP_PROTOCOL == generic ]; then
        if [ "$status" -le $EP_STATUS_WAIVED ]; then
            status=0
        else
            status=1
        fi
    fi

    exit "$status"
}

# Check if an assertion name is valid.
# Args: name
function ep_name_is_valid()
{
    declare -r name="$1"
    if [[ "$name" == *[^A-Za-z0-9_-]* ]]; then
        return 1
    else
        return 0
    fi
}

# Check if an assertion descriptive text is valid.
# Args: text
function ep_text_is_valid()
{
    declare -r text="$1"
    if [[ "$text" == *[[:cntrl:]]* ]]; then
        return 1
    else
        return 0
    fi
}

# Exit the suite immediately with PANICKED status, skipping (the rest of)
# teardown, optionally outputting a message to stderr.
# Args: [message...]
function ep_panic()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    _ep_fini $EP_STATUS_PANICKED
}

# Exit the suite with ERRORED status, optionally outputting a message to
# stderr.
# Args: [message...]
function ep_error()
{
    if [ $# != 0 ]; then
        echo "$@" >&2
    fi
    exit 1
}

# Register an assertion status.
# Args: status
function _ep_register_status()
{
    declare -r status="$1"
    declare status_str
    status_str=`ep_status_to_str "\$status"`
    declare -r count_var="_EP_COUNT_$status_str"
    eval "$count_var=$((count_var+1))"
}

# Parse ep_test_begin arguments into a parameter array and an extra argument
# array.
# Args: _param_array _extra_array [ep_test_begin_arg...]
function _ep_test_begin_parse_args()
{
    declare -r _param_array="$1";   shift
    declare -r _extra_array="$1";   shift
    declare _skipped=false
    declare _waived=false
    declare _expected_status=0
    declare _brief=
    declare _failure=
    declare _name=
    declare _args_expr

    _args_expr=`getopt --name ${FUNCNAME[0]} \
                       --options +dwe:b:f: \
                       --longoptions disabled,waived,expected-status: \
                       --longoptions brief:,failure: \
                       -- "$@"`
    eval set -- "$_args_expr"

    while true; do
        case "$1" in
            -d|--disabled)
                _skipped=true
                shift
                ;;
            -w|--waived)
                _waived=true
                shift
                ;;
            -e|--expected-status)
                _expected_status="$2";
                if [[ "$_expected_status" == "" ||
                      "$_expected_status" == *[^" "0-9]* ]]; then
                    ep_abort "Invalid -e/--expected-status option value: $2"
                fi
                shift 2
                ;;
            -b|--brief)
                if ! ep_text_is_valid "$2"; then
                    ep_abort "Invalid -b/--brief option value: $2"
                fi
                _brief="$2"
                shift 2
                ;;
            -f|--failure)
                if ! ep_text_is_valid "$2"; then
                    ep_abort "Invalid -f/--failure option value: $2"
                fi
                _failure="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                ep_abort "Unknown option: $1"
                ;;
        esac
    done

    if [ $# == 0 ]; then
        ep_abort "Invalid number of positional arguments"
    fi
    _name="$1"
    shift
    ep_abort_if_not ep_name_is_valid "$_name"

    eval "$_param_array"'=(
                            "$_skipped"
                            "$_waived"
                            "$_expected_status"
                            "$_brief"
                            "$_failure"
                            "$_name"
                          )
         '"$_extra_array"'=("$@")'
}

# Setup a test execution using positional arguments in the order produced by
# _ep_test_begin_parse_args.
# Args: skipped waived expected_status brief failure name
function _ep_test_begin_positional()
{
    declare skipped="$1";           shift
    declare waived="$1";            shift
    declare expected_status="$1";   shift
    declare brief="$1";             shift
    declare failure="$1";           shift
    declare name="$1";              shift

    # "Enter" the assertion
    ep_strstack_push _EP_NAME_STACK / "$name"

    # Disable skipping if the path matches "ENABLE" filter
    if ep_path_filter "$_EP_NAME_STACK" true ENABLE false; then
        skipped=false
    fi

    # Enable skipping if the path doesn't match "INCLUDE" filter
    if ! ep_path_filter "$_EP_NAME_STACK" true INCLUDE true; then
        skipped=true
    fi

    # Disable waiving if the path matches "CLAIM" filter
    if ep_path_filter "$_EP_NAME_STACK" true CLAIM false; then
        waived=false
    fi

    # Export "skipped" flag, so if the command is skipped it could exit
    # immediately
    _EP_SKIPPED="$skipped"

    # Export "waived" flag, so ep_test_end could ignore assertion status.
    _EP_WAIVED="$waived"

    # Remember expected status - to be compared to the command exit status
    _EP_EXPECTED_STATUS="$expected_status"

    # Remember failure reason - to be logged on failure
    _EP_FAILURE_REASON="$failure"

    _ep_log_msg "STRUCT BEGIN '$_EP_NAME_STACK'${brief:+ $brief}"

    # Disable errexit so a failed command doesn't exit this shell
    ep_attrs_push +o errexit
}

# Setup a test execution.
#
# Args: [option...] [--] name
#
# Options:
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#   -e, --expected-status=STATUS    Expect STATUS exit status. Default is 0.
#   -b, --brief=TEXT                Attach TEXT brief description to the
#                                   assertion.
#   -f, --failure=TEXT              Attach TEXT failure reason to the
#                                   assertion.
#
function ep_test_begin()
{
    declare -a param_array
    declare -a extra_array
    _ep_test_begin_parse_args param_array extra_array "$@"
    if [ ${#extra_array[@]} != 0 ]; then
        ep_abort "Invalid number of positional arguments"
    fi
    _ep_test_begin_positional "${param_array[@]}"
}

# Conclude a test execution.
function ep_test_end()
{
    # Grab the last status, first thing
    declare status=$?
    declare msg
    # Restore errexit state
    ep_attrs_pop

    ep_abort_if_not [ ${_EP_EXPECTED_STATUS+set} ]
    if [ $status == "$_EP_EXPECTED_STATUS" ]; then
        status=$EP_STATUS_PASSED
    else
        status=$EP_STATUS_FAILED
    fi
    unset _EP_EXPECTED_STATUS

    ep_abort_if_not [ ${_EP_WAIVED+set} ]
    if $_EP_WAIVED &&
        (($status >= $EP_STATUS_PASSED && $status <= $EP_STATUS_FAILED)); then
        status=$EP_STATUS_WAIVED
    fi
    _EP_WAIVED=false

    ep_abort_if_not [ ${_EP_SKIPPED+set} ]
    if $_EP_SKIPPED; then
        status=$EP_STATUS_SKIPPED
    fi
    _EP_SKIPPED=false

    ep_abort_if_not ep_status_is_valid $status
    msg="STRUCT END   '$_EP_NAME_STACK' `ep_status_to_str $status`"
    if [ $status == $EP_STATUS_WAIVED ] ||
       [ $status == $EP_STATUS_FAILED ]; then
        msg="$msg${_EP_FAILURE_REASON:+ $_EP_FAILURE_REASON}"
    fi
    unset _EP_FAILURE_REASON
    _ep_log_msg "$msg"

    # "Exit" the assertion
    ep_strstack_pop _EP_NAME_STACK /
    _ep_register_status $status
    if [ $status -ge $EP_STATUS_PANICKED ]; then
        _ep_fini $status
    fi
}

# Execute a test command invoking an executable, or a function running in a
# subshell; either of them should adhere to the generic protocol.
# Args: ep_test_begin_arg... [command [arg...]]
function ep_test()
{
    declare -a param_array
    declare -a extra_array
    _ep_test_begin_parse_args param_array extra_array "$@"
    _ep_test_begin_positional "${param_array[@]}"
    if ! $_EP_SKIPPED; then
        if [ ${#extra_array[@]} != 0 ]; then
            "${extra_array[@]}"
        else
            true
        fi
    fi
    ep_test_end
}

# Parse ep_suite_begin arguments into a parameter array and an extra argument
# array.
# Args: _param_array _extra_array [ep_suite_begin_arg...]
function _ep_suite_begin_parse_args()
{
    declare -r _param_array="$1";   shift
    declare -r _extra_array="$1";   shift
    declare _skipped=false
    declare _waived=false
    declare _expected_status=0
    declare _brief=
    declare _failure=
    declare _name=
    declare _args_expr

    _args_expr=`getopt --name ${FUNCNAME[0]} \
                       --options +dwb:f: \
                       --longoptions disabled,waived,brief:,failure: \
                       -- "$@"`
    eval set -- "$_args_expr"

    while true; do
        case "$1" in
            -d|--disabled)
                _skipped=true
                shift
                ;;
            -w|--waived)
                _waived=true
                shift
                ;;
            -b|--brief)
                if ! ep_text_is_valid "$2"; then
                    ep_abort "Invalid -b/--brief option value: $2"
                fi
                _brief="$2"
                shift 2
                ;;
            -f|--failure)
                if ! ep_text_is_valid "$2"; then
                    ep_abort "Invalid -f/--failure option value: $2"
                fi
                _failure="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                ep_abort "Unknown option: $1"
                ;;
        esac
    done

    if [ $# == 0 ]; then
        ep_abort "Invalid number of positional arguments"
    fi
    _name="$1"
    shift
    ep_abort_if_not ep_name_is_valid "$_name"

    eval "$_param_array"'=(
                            "$_skipped"
                            "$_waived"
                            "$_brief"
                            "$_failure"
                            "$_name"
                          )
         '"$_extra_array"'=("$@")'
}

# Setup a suite execution using positional arguments in the order produced by
# _ep_suite_begin_parse_args.
# Args: skipped waived brief failure name
function _ep_suite_begin_positional()
{
    declare skipped="$1";           shift
    declare waived="$1";            shift
    declare brief="$1";             shift
    declare failure="$1";           shift
    declare name="$1";              shift

    # "Enter" the assertion
    ep_strstack_push _EP_NAME_STACK / "$name"

    # Disable skipping if path matches "ENABLE" filter
    if ep_path_filter "$_EP_NAME_STACK" false ENABLE false; then
        skipped=false
    fi

    # Enable skipping if path doesn't match "INCLUDE" filter
    if ! ep_path_filter "$_EP_NAME_STACK" false INCLUDE true; then
        skipped=true
    fi

    # Disable waiving if path matches "CLAIM" filter
    if ep_path_filter "$_EP_NAME_STACK" false CLAIM false; then
        waived=false
    fi

    # Export "skipped" flag, so if the command is skipped it could exit
    # immediately
    _EP_SKIPPED="$skipped"

    # Export "waived" flag, so ep_suite_end could ignore assertion status.
    _EP_WAIVED="$waived"

    # Remember failure reason - to be logged on failure
    _EP_FAILURE_REASON="$failure"

    _ep_log_msg "STRUCT BEGIN '$_EP_NAME_STACK'${brief:+ $brief}"

    # Disable errexit so a failed command doesn't exit this shell
    ep_attrs_push +o errexit
}

# Setup a suite execution.
#
# Args: [option...] [--] name
#
# Options:
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#   -b, --brief=TEXT                Attach TEXT brief description to the
#                                   assertion.
#   -f, --failure=TEXT              Attach TEXT failure reason to the
#                                   assertion.
#
function ep_suite_begin()
{
    declare -a param_array
    declare -a extra_array
    _ep_suite_begin_parse_args param_array extra_array "$@"
    if [ ${#extra_array[@]} != 0 ]; then
        ep_abort "Invalid number of positional arguments"
    fi
    _ep_suite_begin_positional "${param_array[@]}"
}

# Conclude a suite execution.
function ep_suite_end()
{
    # Grab the last status, first thing
    declare status=$?
    declare msg
    # Restore errexit state
    ep_attrs_pop

    ep_abort_if_not [ ${_EP_WAIVED+set} ]
    if $_EP_WAIVED &&
        (($status >= $EP_STATUS_PASSED && $status <= $EP_STATUS_FAILED)); then
        status=$EP_STATUS_WAIVED
    fi
    _EP_WAIVED=false

    ep_abort_if_not [ ${_EP_SKIPPED+set} ]
    if $_EP_SKIPPED; then
        status=$EP_STATUS_SKIPPED
    fi
    _EP_SKIPPED=false

    ep_abort_if_not ep_status_is_valid $status
    msg="STRUCT END   '$_EP_NAME_STACK' `ep_status_to_str $status`"
    if [ $status == $EP_STATUS_WAIVED ] ||
       [ $status == $EP_STATUS_FAILED ]; then
        msg="$msg${_EP_FAILURE_REASON:+ $_EP_FAILURE_REASON}"
    fi
    unset _EP_FAILURE_REASON
    _ep_log_msg "$msg"

    # "Exit" the assertion
    ep_strstack_pop _EP_NAME_STACK /
    _ep_register_status $status
    if [ $status -ge $EP_STATUS_PANICKED ]; then
        _ep_fini $status
    fi
}

# Execute a suite command invoking an executable, or a function running in a
# subshell; either of them should adhere to the suite protocol.
# Args: ep_suite_begin_arg... [command [arg...]]
function ep_suite()
{
    declare -a param_array
    declare -a extra_array
    _ep_suite_begin_parse_args param_array extra_array "$@"
    _ep_suite_begin_positional "${param_array[@]}"
    if ! $_EP_SKIPPED; then
        if [ ${#extra_array[@]} != 0 ]; then
            "${extra_array[@]}"
        else
            (
                ep_suite_init
            )
        fi
    fi
    ep_suite_end
}

# Handle EXIT trap
function _ep_trap_exit()
{
    # Grab the last status, first thing
    declare status="$?"
    declare teardown_status=

    # Execute teardown in a subshell
    ep_attrs_push +o errexit
    (
        ep_attrs_pop
        ep_teardown_exec_all
    )
    teardown_status=$?
    ep_attrs_pop

    # If teardown failed
    if [ $teardown_status != 0 ]; then
        status=$EP_STATUS_PANICKED
    # else, if exiting with failure
    elif [ $status != 0 ] || [ $_EP_COUNT_ERRORED != 0 ]; then
        status=$EP_STATUS_ERRORED
    # else, if there were failed assertions
    elif [ $_EP_COUNT_FAILED != 0 ]; then
        status=$EP_STATUS_FAILED
    # else, if there were waived assertions
    elif [ $_EP_COUNT_WAIVED != 0 ]; then
        status=$EP_STATUS_WAIVED
    # else, if there were passed assertions
    elif [ $_EP_COUNT_PASSED != 0 ]; then
        status=$EP_STATUS_PASSED
    # else, if there were skipped assertions
    elif [ $_EP_COUNT_SKIPPED != 0 ]; then
        status=$EP_STATUS_SKIPPED
    else
        status=$EP_STATUS_PASSED
    fi

    _ep_fini $status
}

# Handle SIGABRT
function _ep_trap_sigabrt()
{
    trap - SIGABRT
    ep_backtrace 1 >&2
    _ep_fini $EP_STATUS_ABORTED
}

fi # _EP_SH
