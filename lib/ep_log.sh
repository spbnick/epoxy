#
# Logging system
#
# Copyright (c) 2012-2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_LOG_SH+set} ]; then
declare -r _EP_LOG_SH=

. thud_misc.sh

# Original stdout FD
declare -r _EP_LOG_STDOUT_FD=5
# Original stderr FD
declare -r _EP_LOG_STDERR_FD=6

# Stdout and stderr output FD
declare -r _EP_LOG_OUTPUT_FD=7
# Messages output FD
declare -r _EP_LOG_MESSAGES_FD=8
# Sync input FD
declare -r _EP_LOG_SYNC_FD=9

# Log pipe PID
declare _EP_LOG_PID

# Setup test suite logging.
# Args: file filter filter_opts cook
function _ep_log_init()
{
    declare -r file="$1"; shift
    declare -r filter="$1"; shift
    declare -r filter_opts="$1"; shift
    declare -r cook="$1"; shift

    thud_assert 'thud_is_bool "$filter"'
    thud_assert 'thud_is_bool "$cook"'
    thud_assert 'test -d "$EP_TMPDIR"'

    declare -r output_fifo="$EP_TMPDIR/output.fifo"
    declare -r messages_fifo="$EP_TMPDIR/messages.fifo"
    declare -r sync_fifo="$EP_TMPDIR/sync.fifo"
    declare pipe_cmd='ep_log_mix "$o" "$m" "$s"'

    if [ -n "$file" ]; then
        pipe_cmd="$pipe_cmd"' | tee "$f"'
    fi

    if $filter; then
        pipe_cmd="$pipe_cmd | ep_log_filter $filter_opts"
    fi

    if $cook; then
        pipe_cmd="$pipe_cmd | ep_log_cook"
    fi

    mkfifo "$output_fifo"
    mkfifo "$messages_fifo"
    mkfifo "$sync_fifo"

    # Start log-mixing process in a separate session and thus process group,
    # so it doesn't get killed by signals sent to our process group.
    o="$output_fifo" m="$messages_fifo" s="$sync_fifo" f="$file" \
        setsid bash -c "export -n o m s f; $pipe_cmd" 0</dev/null &
    _EP_LOG_PID="$!"

    # Open FIFO's and setup redirections
    eval "exec $_EP_LOG_OUTPUT_FD>\"\$output_fifo\" \
               $_EP_LOG_MESSAGES_FD>\"\$messages_fifo\" \
               $_EP_LOG_SYNC_FD<\"\$sync_fifo\" \
               $_EP_LOG_STDOUT_FD>&1- $_EP_LOG_STDERR_FD>&2- \
               1>&$_EP_LOG_OUTPUT_FD 2>&$_EP_LOG_OUTPUT_FD"
}

# Finalize test suite logging.
function _ep_log_fini()
{
    # Close FIFOs and restore stdout and stderr
    eval "exec $_EP_LOG_OUTPUT_FD>&- \
               $_EP_LOG_MESSAGES_FD>&- \
               $_EP_LOG_SYNC_FD<&- \
               1>&$_EP_LOG_STDOUT_FD- \
               2>&$_EP_LOG_STDERR_FD-"

    # Wait for the pipe to finish
    wait "$_EP_LOG_PID"
}

# Log a message
# Args: [message_word...]
function _ep_log_msg()
{
    declare newline
    echo "$@" >&$_EP_LOG_MESSAGES_FD
    read -u $_EP_LOG_SYNC_FD newline
}

fi # _EP_LOG_SH
