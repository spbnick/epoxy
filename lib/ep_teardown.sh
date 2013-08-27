#
# Teardown handling
#
# Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_TEARDOWN_SH+set} ]; then
declare -r _EP_TEARDOWN_SH=

. thud_arr.sh
. thud_misc.sh

# Teardown command argc array
declare -a _EP_TEARDOWN_ARGC=()
# Teardown command argv array
declare -a _EP_TEARDOWN_ARGV=()

# Push a command to the teardown command stack.
# Args: ...
function ep_teardown_push()
{
    thud_arr_push _EP_TEARDOWN_ARGC $#
    thud_arr_push _EP_TEARDOWN_ARGV "$@"
}

# Pop commands from the teardown command stack.
# Args: [num_commands]
function ep_teardown_pop()
{
    declare num_commands="${1:-1}"
    thud_assert '[ "$num_commands" -le ${#_EP_TEARDOWN_ARGC[@]} ]'
    for ((; num_commands > 0; num_commands--)); do
        thud_arr_pop _EP_TEARDOWN_ARGV \
                     `thud_arr_peek _EP_TEARDOWN_ARGC`
        thud_arr_pop _EP_TEARDOWN_ARGC
    done
}

# Pop all commands from the teardown command stack.
function ep_teardown_pop_all()
{
    _EP_TEARDOWN_ARGC=()
    _EP_TEARDOWN_ARGV=()
}

# Execute and pop commands from the teardown command stack.
# Args: [num_commands]
function ep_teardown_exec()
{
    declare num_commands="${1:-1}"
    thud_assert '[ "$num_commands" -le ${#_EP_TEARDOWN_ARGC[@]} ]'
    for ((; num_commands > 0; num_commands--)); do
        "${_EP_TEARDOWN_ARGV[@]: -${_EP_TEARDOWN_ARGC[${#_EP_TEARDOWN_ARGC[@]}-1]}}"
        ep_teardown_pop
    done
}

# Execute and pop all commands from the teardown command stack.
function ep_teardown_exec_all()
{
    ep_teardown_exec "${#_EP_TEARDOWN_ARGC[@]}"
}

fi # _EP_TEARDOWN_SH
