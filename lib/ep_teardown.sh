#
# Teardown handling
#
# Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_TEARDOWN_SH+set} ]; then
declare -r _BT_TEARDOWN_SH=

. bt_util.sh

# Teardown command argc array
declare -a _BT_TEARDOWN_ARGC
# Teardown command argv array
declare -a _BT_TEARDOWN_ARGV

# Push a command to the teardown command stack.
# Args: ...
function bt_teardown_push()
{
    bt_arrstack_push _BT_TEARDOWN_ARGC $#
    bt_arrstack_push _BT_TEARDOWN_ARGV "$@"
}

# Pop commands from the teardown command stack.
# Args: [num_commands]
function bt_teardown_pop()
{
    declare num_commands="${1:-1}"
    bt_abort_assert [ "$num_commands" -le ${#_BT_TEARDOWN_ARGC[@]} ]
    for ((; num_commands > 0; num_commands--)); do
        bt_arrstack_pop _BT_TEARDOWN_ARGV \
                        `bt_arrstack_peek _BT_TEARDOWN_ARGC`
        bt_arrstack_pop _BT_TEARDOWN_ARGC
    done
}

# Execute and pop commands from the teardown command stack.
# Args: [num_commands]
function bt_teardown_exec()
{
    declare num_commands="${1:-1}"
    bt_abort_assert [ "$num_commands" -le ${#_BT_TEARDOWN_ARGC[@]} ]
    for ((; num_commands > 0; num_commands--)); do
        "${_BT_TEARDOWN_ARGV[@]: -${_BT_TEARDOWN_ARGC[${#_BT_TEARDOWN_ARGC[@]}-1]}}"
        bt_teardown_pop
    done
}

# Execute and pop all commands from the teardown command stack.
function bt_teardown_exec_all()
{
    bt_teardown_exec "${#_BT_TEARDOWN_ARGC[@]}"
}

fi # _BT_TEARDOWN_SH
