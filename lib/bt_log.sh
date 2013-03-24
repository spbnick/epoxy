#
# Logging system
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_LOG_SH+set} ]; then
declare -r _BT_LOG_SH=

# Original stdout FD
declare -r BT_LOG_STDOUT_FD=5
# Original stderr FD
declare -r BT_LOG_STDERR_FD=6

# Stdout and stderr output FD
declare -r BT_LOG_OUTPUT_FD=7
# Messages output FD
declare -r BT_LOG_MESSAGES_FD=8
# Sync input FD
declare -r BT_LOG_SYNC_FD=9

# Log file
declare _BT_LOG_FILE
# Output filtering enabled
declare _BT_LOG_FILTER
# Output filter maximum level
declare _BT_LOG_FILTER_LEVEL
# Output filter minimum depth
declare _BT_LOG_FILTER_TOP
# Output filter maximum depth
declare _BT_LOG_FILTER_BOTTOM
# Output filter status
declare _BT_LOG_FILTER_STATUS
# Output cooking enabled
declare _BT_LOG_COOK
# Log pipe PID
declare _BT_LOG_PID

# Setup test suite logging.
function _bt_log_init()
{
    declare -r output_fifo="$BT_TMPDIR/output.fifo"
    declare -r messages_fifo="$BT_TMPDIR/messages.fifo"
    declare -r sync_fifo="$BT_TMPDIR/sync.fifo"
    declare pipe_cmd='bt_log_mix "$o" "$m" "$s"'

    if [ -n "$_BT_LOG_FILE" ]; then
        pipe_cmd="$pipe_cmd"' | tee "$f"'
    fi

    if $_BT_LOG_FILTER; then
        pipe_cmd="$pipe_cmd | bt_log_filter \
                                --level=$_BT_LOG_FILTER_LEVEL \
                                --top=$_BT_LOG_FILTER_TOP \
                                --bottom=$_BT_LOG_FILTER_BOTTOM \
                                --status=$_BT_LOG_FILTER_STATUS"
    fi

    if $_BT_LOG_COOK; then
        pipe_cmd="$pipe_cmd | bt_log_cook"
    fi

    mkfifo "$output_fifo"
    mkfifo "$messages_fifo"
    mkfifo "$sync_fifo"

    # Start log-mixing process in a separate session and thus process group,
    # so it doesn't get killed by signals sent to our process group.
    o="$output_fifo" m="$messages_fifo" s="$sync_fifo" f="$_BT_LOG_FILE" \
        setsid bash -c "export -n o m s f; $pipe_cmd" 0</dev/null &
    _BT_LOG_PID="$!"

    # Open FIFO's and setup redirections
    eval "exec $BT_LOG_OUTPUT_FD>\"\$output_fifo\" \
               $BT_LOG_MESSAGES_FD>\"\$messages_fifo\" \
               $BT_LOG_SYNC_FD<\"\$sync_fifo\" \
               $BT_LOG_STDOUT_FD>&1- $BT_LOG_STDERR_FD>&2- \
               1>&$BT_LOG_OUTPUT_FD 2>&$BT_LOG_OUTPUT_FD"
}

# Finalize test suite logging.
function _bt_log_fini()
{
    # Close FIFOs and restore stdout and stderr
    eval "exec $BT_LOG_OUTPUT_FD>&- \
               $BT_LOG_MESSAGES_FD>&- \
               $BT_LOG_SYNC_FD<&- \
               1>&$BT_LOG_STDOUT_FD- \
               2>&$BT_LOG_STDERR_FD-"

    # Wait for the pipe to finish
    wait "$_BT_LOG_PID"
}

# Log a message
# Args: [message_word...]
function _bt_log_msg()
{
    declare newline
    echo "$@" >&$BT_LOG_MESSAGES_FD
    read -u $BT_LOG_SYNC_FD newline
}

fi # _BT_LOG_SH
