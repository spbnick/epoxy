#
# Initialize a (sub)shell
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
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

if [ $BASH_SUBSHELL == "${_BT_SHELL_INIT_SUBSHELL:-}" ]; then
    bt_abort "Re-initializing a (sub)shell"
fi

# Last initialized subshell depth
declare _BT_SHELL_INIT_SUBSHELL=$BASH_SUBSHELL

# Set PID that bt_abort should send SIGABRT to - the PID of the (sub)shell
# being initialized, if can be retrieved
if [ -n "${BASHPID+set}" ]; then
    BT_ABORT_PID="$BASHPID"
elif [ -r /proc/self/stat ]; then
    declare _BT_SHELL_INIT_DISCARD=
    read -r BT_ABORT_PID _BT_SHELL_INIT_DISCARD < /proc/self/stat
    unset _BT_SHELL_INIT_DISCARD
fi
