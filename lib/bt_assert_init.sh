#
# Initialize an assertion (sub)shell
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

. bt_shell_init.sh
. bt_util.sh

# Reset SIGABRT handler possibly set by surrounding test.
trap - SIGABRT

bt_abort_assert bt_bool_is_valid "${_BT_SKIPPED-false}"
bt_abort_assert bt_bool_is_valid "${_BT_WAIVED-false}"

# If entering a skipped script
if ${_BT_SKIPPED:-false}; then
    exit 0
fi

# If entering a waived script
if ${_BT_WAIVED-false}; then
    exit 0
fi
