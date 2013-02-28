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

# First FD reserved for the user
declare -r BT_USER_FD1=3
# Second FD reserved for the user
declare -r BT_USER_FD2=4
# Original stdout FD
declare -r BT_STDOUT_FD=5
# Original stderr FD
declare -r BT_STDERR_FD=6
# Log stdout and stderr output FD
declare -r BT_LOG_OUTPUT_FD=7
# Log messages output FD
declare -r BT_LOG_MESSAGES_FD=8
# Log sync input FD
declare -r BT_LOG_SYNC_FD=9

# Suite command-line arguments
declare -a BT_SUITE_ARGS=()

# List of inter-suite environment variables.
declare -a _BT_EXPORT_LIST=()

# Declare inter-suite environment variables.
# Args: [_name...]
function bt_export()
{
    bt_arrstack_push _BT_EXPORT_LIST "$@"
    export -- "$@"
}

# Protocol for suites (nothing, "generic", or "suite")
bt_export BT_PROTOCOL

# NOTE: using export instead of declare -x as a bash 3.x bug workaround
# Glob pattern matching assertions to (not) include in the run
bt_export BT_INCLUDE BT_DONT_INCLUDE
# Glob pattern matching assertions to (not) remove disabled status from
bt_export BT_ENABLE BT_DONT_ENABLE
# Glob pattern matching assertions to (not) remove waived status from
bt_export BT_UNWAIVE BT_DONT_UNWAIVE

# Assertion name stack
bt_export _BT_NAME_STACK
# "Skipped" flag - exit assertion shell immediately, if "true".
bt_export _BT_SKIPPED
# "Waived" flag - ignore assertion status, if "true".
bt_export _BT_WAIVED

# Temporary directory
bt_export BT_TMPDIR

# If "true", the log setup was done
bt_export _BT_LOG_SETUP

# Last initialized subshell depth
declare _BT_SHELL_INIT_SUBSHELL

# Protocol for this suite ("generic", or "suite")
declare _BT_PROTOCOL

# If "true", the temporary directory was created by this suite
declare _BT_TMPDIR_OWNER

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

# Teardown command argc array
declare -a _BT_TEARDOWN_ARGC
# Teardown command argv array
declare -a _BT_TEARDOWN_ARGV

# Initialize a (sub)shell.
function _bt_shell_init()
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

    if [ "$BASH_SUBSHELL" == "${_BT_SHELL_INIT_SUBSHELL:-}" ]; then
        bt_abort "Re-initializing a (sub)shell"
    fi

    # Last initialized subshell depth
    _BT_SHELL_INIT_SUBSHELL="$BASH_SUBSHELL"

    # Set PID that bt_abort should send SIGABRT to - the PID of the (sub)shell
    # being initialized, if can be retrieved
    if [ -n "${BASHPID+set}" ]; then
        BT_ABORT_PID="$BASHPID"
    elif [ -r /proc/self/stat ]; then
        declare discard=
        read -r BT_ABORT_PID discard < /proc/self/stat
    fi

    bt_abort_assert bt_bool_is_valid "${_BT_SKIPPED-false}"

    # If entering a skipped assertion shell
    if ${_BT_SKIPPED:-false}; then
        exit 0
    fi
}

# Output usage information
function _bt_usage()
{
    echo "\
Usage: `basename \"\$0\"` [OPTION]... [PATTERN]... [-- [SUITE_ARG]...]
Execute test suite.

Arguments:

    PATTERN                 Verify assertions matching PATTERN.

Options:

    -h, --help              Output this help message and exit.

    -i, --include=PATTERN   Verify assertions matching PATTERN.
    -e, --exclude=PATTERN,
    --dont-include=PATTERN  Don't verify assertions matching PATTERN.

    -u, --unwaive=PATTERN   Remove \"waived\" status from assertions matching
                            PATTERN.
    --dont-unwaive=PATTERN  Don't remove \"waived\" status from assertions
                            matching PATTERN.

    -e, --enable=PATTERN    Enable assertions matching PATTERN.
    --dont-enable=PATTERN   Don't enable assertions matching PATTERN.

Any arguments specified after \"--\" are passed to the suite.
"
}

# Parse command line arguments, extracting framework-specific arguments and
# storing suite arguments in BT_SUITE_ARGS array.
# Args: [arg...]
function _bt_parse_args()
{
    # Collect framework arguments
    declare args=()
    while [ $# != 0 ]; do
        if [ "$1" == "--" ]; then
            shift;
            break;
        fi
        args[${#args[@]}]="$1"
        shift
    done

    # Store suite arguments
    BT_SUITE_ARGS=("$@")

    # If there are no framework arguments
    if [ "${#args[@]}" == 0 ]; then
        return
    fi

    # Parse framework arguments
    declare args_expr
    args_expr=`getopt --name \`basename "\$0"\` \
                      --options hi:e:u:e: \
                      --longoptions help,include:,exclude:,dont-include: \
                      --longoptions unwaive:dont-unwaive:enable:dont-enable: \
                      -- "${args[@]}"`
    eval set -- "$args_expr"

    # Read framework option arguments
    while true; do
        case "$1" in
            -h|--help)
                _bt_usage; exit 0;;
            -i|--include)
                bt_glob_var_or BT_INCLUDE       "$2"; shift 2;;
            -e|--exclude|--dont-include)
                bt_glob_var_or BT_DONT_INCLUDE  "$2"; shift 2;;
            -u|--unwaive)
                bt_glob_var_or BT_UNWAIVE       "$2"; shift 2;;
            --dont-unwaive)
                bt_glob_var_or BT_DONT_UNWAIVE  "$2"; shift 2;;
            -e|--enable)
                bt_glob_var_or BT_ENABLE        "$2"; shift 2;;
            --dont-enable)
                bt_glob_var_or BT_DONT_ENABLE   "$2"; shift 2;;
            --) shift; break;;
            *) echo "Unknown option: $1" >&2; exit 127 ;;
        esac
    done

    # Read framework positional arguments
    while [ $# != 0 ]; do
        if [ "$1" == "--" ]; then
            shift
            break
        fi
        bt_glob_var_or BT_INCLUDE "$1"
        shift
    done
}

# Setup test suite logging.
function _bt_init_log()
{
    declare -r output_fifo="$BT_TMPDIR/output.fifo"
    declare -r messages_fifo="$BT_TMPDIR/messages.fifo"
    declare -r sync_fifo="$BT_TMPDIR/sync.fifo"

    mkfifo "$output_fifo"
    mkfifo "$messages_fifo"
    mkfifo "$sync_fifo"

    # Move original stdout and stderr
    eval "exec $BT_STDOUT_FD>&1- $BT_STDERR_FD>&2-"

    # Start log-mixing process
    bt_log_mix "$output_fifo" "$messages_fifo" "$sync_fifo" \
                0</dev/null 1>&$BT_STDOUT_FD 2>&$BT_STDERR_FD &

    # Open FIFO's and setup redirections
    eval "exec $BT_LOG_OUTPUT_FD>\"\$output_fifo\" \
               $BT_LOG_MESSAGES_FD>\"\$messages_fifo\" \
               $BT_LOG_SYNC_FD<\"\$sync_fifo\" \
               1>&$BT_LOG_OUTPUT_FD \
               2>&$BT_LOG_OUTPUT_FD"
}

# Log a message
# Args: [message_word...]
function _bt_log()
{
    declare newline
    echo "$@" >&$BT_LOG_MESSAGES_FD
    read -u $BT_LOG_SYNC_FD newline
}

# Initialize a suite shell, parse command line arguments, extracting
# framework-specific arguments and storing suite arguments in BT_SUITE_ARGS
# array.
# Args: [cmdline_arg...]
function bt_suite_init()
{
    # Initialize a generic shell
    _bt_shell_init

    # Parse command line arguments
    _bt_parse_args "$@"

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

    # Create temporary directory, if none specified
    if [ -z "${BT_TMPDIR+set}" ]; then
        BT_TMPDIR=`mktemp -d -t bt.XXXXXXXXXX`
        _BT_TMPDIR_OWNER=true
    else
        _BT_TMPDIR_OWNER=false
    fi

    # Setup logging, if not done yet
    bt_abort_assert bt_bool_is_valid "${_BT_LOG_SETUP-false}"
    if ! ${_BT_LOG_SETUP-false}; then
        _bt_init_log
        _BT_LOG_SETUP=true
    fi

    _bt_log "STRUCT ENTER '$_BT_NAME_STACK'"
}

# Cleanup a suite shell.
function bt_suite_cleanup()
{
    unset -- "${_BT_EXPORT_LIST[@]}"
    trap - SIGABRT
}

# Initialize a test shell.
function bt_test_init()
{
    # Cleanup the possible inherited suite shell
    bt_suite_cleanup
    # Initialize a generic shell
    _bt_shell_init
}


# Finalize the test suite.
# Args: status
function _bt_fini()
{
    declare status="$1"
    bt_abort_assert bt_status_is_valid "$status"

    trap - EXIT

    _bt_log "STRUCT EXIT  '$_BT_NAME_STACK' `bt_status_to_str $status`"

    if [ $_BT_PROTOCOL == generic ]; then
        if [ "$status" -le $BT_STATUS_WAIVED ]; then
            status=0
        else
            status=1
        fi
    fi

    # Remove temporary directory, if created by this suite
    if $_BT_TMPDIR_OWNER; then
        rm -R "$BT_TMPDIR"
    fi

    exit "$status"
}

# Check if an assertion name is valid.
# Args: name
function bt_name_is_valid()
{
    declare -r name="$1"
    if [[ "$name" == *[^A-Za-z0-9_-]* ]]; then
        return 1
    else
        return 0
    fi
}

# Match an assertion path against a negative pattern.
# Args: pattern path
function bt_path_match_negative()
{
    declare -r pattern="$1"
    declare -r path="$2"

    # If it's the exact node
    if bt_glob_aborting "$pattern" "$path" ||
       # Or a child
       bt_glob_aborting --text-prefix "$pattern/" "$path"; then
        return 0
    else
        return 1
    fi
}

# Match either a final or a partial assertion path against a positive pattern.
# Args: pattern path final
function bt_path_match_positive()
{
    declare -r pattern="$1"
    declare -r path="$2"
    declare -r final="$3"

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
}

# Match either a final or a partial assertion path against a filter - a pair
# of optional pattern variables - one that should match and one that
# shouldn't.
# Args: path final filter default
#
# The logic table is this:
#
#   INCLUDE     EXCLUDE     RESULT
#   -           -           D
#   -           N           Y
#   -           Y           N
#   N           -           N
#   N           N           N
#   N           Y           N
#   Y           -           Y
#   Y           N           Y
#   Y           Y           N
#
#   - - unset
#   Y - match
#   N - mismatch
#   D - default
#
function bt_path_filter()
{
    declare -r path="$1"
    declare -r final="$2"
    declare -r filter="$3"
    declare -r default="$4"

    declare -r include_var="BT_$filter"
    declare -r exclude_var="BT_DONT_$filter"
    declare include_set
    declare exclude_set
    declare include
    declare exclude
    declare match

    # If include variable is specified
    if [ -n "${!include_var+set}" ]; then
        include_set=true
        bt_path_match_positive "${!include_var}" "$path" "$final" &&
            include=1 || include=0
    else
        include_set=false
    fi

    # If exclude variable is specified
    if [ -n "${!exclude_var+set}" ]; then
        exclude_set=true
        bt_path_match_negative "${!exclude_var}" "$path" &&
            exclude=1 || exclude=0
    else
        exclude_set=false
    fi

    # Combine matching results
    if $include_set; then
        if $exclude_set; then
            match=$((include && !exclude))
        else
            match=$((include))
        fi
    elif $exclude_set; then
        match=$((!exclude))
    else
        $default && match=1 || match=0
    fi

    return $((!match))
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
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#   -e, --expected-status=STATUS    Expect STATUS exit status. Default is 0.
#
function bt_test_begin()
{
    declare skipped=false
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +dwe: \
                         --longoptions disabled,waived,expected-status: \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -d|--disabled)
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
    bt_abort_assert bt_name_is_valid "$name"

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"

    # Disable skipping if the path matches "ENABLE" filter
    if bt_path_filter "$_BT_NAME_STACK" true ENABLE false; then
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
    _BT_SKIPPED="$skipped"

    # Export "waived" flag, so bt_test_end could ignore assertion status.
    _BT_WAIVED="$waived"

    # Remember expected status - to be compared to the command exit status
    _BT_EXPECTED_STATUS="$expected_status"

    _bt_log "STRUCT BEGIN '$_BT_NAME_STACK'"

    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a test execution.
function bt_test_end()
{
    # Grab the last status, first thing
    declare status=$?
    # Restore errexit state
    bt_attrs_pop

    bt_abort_assert [ ${_BT_EXPECTED_STATUS+set} ]
    if [ $status == "$_BT_EXPECTED_STATUS" ]; then
        status=$BT_STATUS_PASSED
    else
        status=$BT_STATUS_FAILED
    fi
    unset _BT_EXPECTED_STATUS

    bt_abort_assert [ ${_BT_WAIVED+set} ]
    if $_BT_WAIVED &&
        (($status >= $BT_STATUS_PASSED && $status <= $BT_STATUS_FAILED)); then
        status=$BT_STATUS_WAIVED
    fi
    _BT_WAIVED=false

    bt_abort_assert [ ${_BT_SKIPPED+set} ]
    if $_BT_SKIPPED; then
        status=$BT_STATUS_SKIPPED
    fi
    _BT_SKIPPED=false

    bt_abort_assert bt_status_is_valid $status
    _bt_log "STRUCT END   '$_BT_NAME_STACK' `bt_status_to_str $status`"
    # "Exit" the assertion
    bt_strstack_pop _BT_NAME_STACK /
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
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#   -e, --expected-status=STATUS    Expect STATUS exit status. Default is 0.
#
function bt_test()
{
    declare disabled=false
    declare waived=false
    declare expected_status=0
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +dwe: \
                         --longoptions disabled,waived,expected-status: \
                         -- "$@"`
    declare -a begin_args=()
    eval set -- "$args"

    while true; do
        case "$1" in
            -d|--disabled)
                disabled=true
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
    bt_abort_assert bt_name_is_valid "$name"

    if $disabled; then
        begin_args[${#begin_args[@]}]="--disabled"
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
    if ! $disabled; then
        "$@"
    fi
    bt_test_end
}

# Setup a suite execution.
#
# Args: [option...] [--] name
#
# Options:
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#
function bt_suite_begin()
{
    declare skipped=false
    declare waived=false
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +dw \
                         --longoptions disabled,waived \
                         -- "$@"`
    eval set -- "$args"

    while true; do
        case "$1" in
            -d|--disabled)
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
    bt_abort_assert bt_name_is_valid "$name"

    # "Enter" the assertion
    bt_strstack_push _BT_NAME_STACK / "$name"

    # Disable skipping if path matches "ENABLE" filter
    if bt_path_filter "$_BT_NAME_STACK" false ENABLE false; then
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
    _BT_SKIPPED="$skipped"

    # Export "waived" flag, so bt_suite_end could ignore assertion status.
    _BT_WAIVED="$waived"

    _bt_log "STRUCT BEGIN '$_BT_NAME_STACK'"

    # Disable errexit so a failed command doesn't exit this shell
    bt_attrs_push +o errexit
}

# Conclude a suite execution.
function bt_suite_end()
{
    # Grab the last status, first thing
    declare status=$?
    # Restore errexit state
    bt_attrs_pop

    bt_abort_assert [ ${_BT_WAIVED+set} ]
    if $_BT_WAIVED &&
        (($status >= $BT_STATUS_PASSED && $status <= $BT_STATUS_FAILED)); then
        status=$BT_STATUS_WAIVED
    fi
    _BT_WAIVED=false

    bt_abort_assert [ ${_BT_SKIPPED+set} ]
    if $_BT_SKIPPED; then
        status=$BT_STATUS_SKIPPED
    fi
    _BT_SKIPPED=false

    bt_abort_assert bt_status_is_valid $status
    _bt_log "STRUCT END   '$_BT_NAME_STACK' `bt_status_to_str $status`"
    # "Exit" the assertion
    bt_strstack_pop _BT_NAME_STACK /
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
#   -d, --disabled                  Mark assertion as disabled.
#   -w, --waived                    Mark assertion as waived.
#
function bt_suite()
{
    declare disabled=false
    declare waived=false
    declare -a opts=()
    declare args=`getopt --name ${FUNCNAME[0]} \
                         --options +dw \
                         --longoptions disabled,waived \
                         -- "$@"`
    declare -a begin_args=()
    eval set -- "$args"

    while true; do
        case "$1" in
            -d|--disabled)
                disabled=true
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
    bt_abort_assert bt_name_is_valid "$name"

    if $disabled; then
        begin_args[${#begin_args[@]}]="--disabled"
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
            bt_suite_init
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
