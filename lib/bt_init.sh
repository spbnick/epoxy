#
# Initialize a test (sub)shell
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

. bt_shell_init.sh
. bt_util.sh
. bt.sh

# Initialize the test
_bt_init

bt_abort_assert bt_bool_is_valid "${_BT_WAIVED-false}"

# If entering a waived test
if ${_BT_WAIVED:-false}; then
    _bt_fini $BT_STATUS_WAIVED
fi
