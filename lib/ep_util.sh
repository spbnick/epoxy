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

# Make sure getopt compatibility isn't enforced
unset GETOPT_COMPATIBLE
# Check if getopt is enhanced and supports quoting
if getopt --test >/dev/null; [ $? != 4 ]; then
    ep_abort_if_not Enhanced getopt not found
fi

fi # _EP_UTIL_SH
