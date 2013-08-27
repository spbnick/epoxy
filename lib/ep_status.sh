#
# Assertion status
#
# Copyright (c) 2012-2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_STATUS_SH+set} ]; then
declare -r _EP_STATUS_SH=

. ep_util.sh
. thud_misc.sh

#
# Status codes
#
# Skipped
declare -r EP_STATUS_SKIPPED=1
# Passed
declare -r EP_STATUS_PASSED=2
# Waived
declare -r EP_STATUS_WAIVED=3
# Failed
declare -r EP_STATUS_FAILED=4
# A setup error occurred
declare -r EP_STATUS_ERRORED=5
# A cleanup error occurred
declare -r EP_STATUS_PANICKED=6
# A coding error occurred
declare -r EP_STATUS_ABORTED=7

# Check if a status code is valid
# Args: status
function ep_status_is_valid()
{
    declare -r status="$1"
    [[ "$status" != "" &&
       "$status" != [^0-9] && \
       "$status" -ge $EP_STATUS_SKIPPED && \
       "$status" -le $EP_STATUS_ABORTED ]]
}

# Convert status code to string
# Args: status_code
# Output: status string
function ep_status_to_str()
{
    declare -r status="$1"

    case "$status" in
        $EP_STATUS_SKIPPED)     echo SKIPPED;;
        $EP_STATUS_PASSED)      echo PASSED;;
        $EP_STATUS_WAIVED)      echo WAIVED;;
        $EP_STATUS_FAILED)      echo FAILED;;
        $EP_STATUS_ERRORED)     echo ERRORED;;
        $EP_STATUS_PANICKED)    echo PANICKED;;
        $EP_STATUS_ABORTED)     echo ABORTED;;
        *) thud_abort "Invalid status code: $status";;
    esac
}

fi # _EP_STATUS_SH
