# Bash test framework - test library
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_TEST_SH+set} ]; then
declare -r _BT_TEST_SH=

# Test protocol status codes
declare -r -i BT_TEST_STATUS_PASSED=1 \
              BT_TEST_STATUS_WAIVED=2 \
              BT_TEST_STATUS_FAILED=3 \
              BT_TEST_STATUS_PANICED=4

# Check if a test stat code is valid
# Args: status
function bt_test_status_is_valid()
{
    declare -r status="$1"
    [[ "$status" != "" && \
       "$status" != [^0-9] && \
       "$status" -ge $BT_TEST_STATUS_PASSED && \
       "$status" -le $BT_TEST_STATUS_PANICED ]]
}

# Convert status code to string
# Args: status_code
# Output: status string
function bt_test_status_to_str()
{
    declare -r status="$1"

    bt_assert bt_test_status_is_valid \$status

    case "$status" in
        $BT_TEST_STATUS_PASSED) echo PASSED;;
        $BT_TEST_STATUS_WAIVED) echo WAIVED;;
        $BT_TEST_STATUS_FAILED) echo FAILED;;
        $BT_TEST_STATUS_PANICED) echo PANICED;;
        *) bt_abort "Unknown test status: $status";;
    esac
}

fi # _BT_TEST_SH
