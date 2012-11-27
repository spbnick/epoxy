#
# Assertion status
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_STATUS_SH+set} ]; then
declare -r _BT_STATUS_SH=

. bt_util.sh

#
# Status codes
#
# Passed
declare -r -i BT_STATUS_PASSED=1
# Waived (not executed)
declare -r -i BT_STATUS_WAIVED=2
# Failed
declare -r -i BT_STATUS_FAILED=3
# A setup error occurred
declare -r -i BT_STATUS_ERRORED=4
# A cleanup error occurred
declare -r -i BT_STATUS_PANICKED=5
# A coding error occurred
declare -r -i BT_STATUS_ABORTED=6

# Check if a status code is valid
# Args: status
function bt_status_is_valid()
{
    declare -r status="$1"
    [[ "$status" != "" &&
       "$status" != [^0-9] && \
       "$status" -ge $BT_STATUS_PASSED && \
       "$status" -le $BT_STATUS_ABORTED ]]
}

# Convert status code to string
# Args: status_code
# Output: status string
function bt_status_to_str()
{
    declare -r status="$1"

    case "$status" in
        $BT_STATUS_PASSED) echo PASSED;;
        $BT_STATUS_WAIVED) echo WAIVED;;
        $BT_STATUS_FAILED) echo FAILED;;
        $BT_STATUS_ERRORED) echo ERRORED;;
        $BT_STATUS_PANICKED) echo PANICKED;;
        $BT_STATUS_ABORTED) echo ABORTED;;
        *) bt_abort "Invalid status code: $status";;
    esac
}

fi # _BT_STATUS_SH
