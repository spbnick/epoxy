#
# Initialize an assertion (sub)shell
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

. bt_shell_init.sh
. bt_util.sh

bt_abort_assert bt_bool_is_valid "${_BT_WAIVED-false}"

# If entering a waived script
if ${_BT_WAIVED-false}; then
    exit 0
fi

# Parse command line arguments
bt_read_args "$@"
