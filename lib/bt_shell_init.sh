#
# Initialize a (sub)shell
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
