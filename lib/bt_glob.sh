#
# Extended glob-like pattern handling library
#
# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_BT_GLOB_SH+set} ]; then
declare -r _BT_GLOB_SH=

# Match a text against an extend glob-like pattern, abort if an error occurs.
# Args: [bt_glob_command_option...] [--] pattern text
function bt_glob_aborting()
{
    declare status=0
    declare stderr
    stderr=`bt_glob "\$@" 2>&1` || status=$?
    if [ "$status" != 0 ] && [ "$status" != 1 ]; then
        bt_abort "$stderr"
    fi
    return $status
}

# Assign a union of a pattern variable contents and another pattern to the
# pattern variable.
# Args: _pvar _p
function bt_glob_var_or()
{
    declare -r _pvar="$1"
    declare -r _p="$2"
    declare _union
    if [ -n "${!_pvar+set}" ]; then
        _union="@(`bt_glob_escape --set-item \"\${!_pvar}\"`|$_p)"
    else
        _union="$_p"
    fi
    eval "$_pvar=\"\$_union\""
}

fi # _BT_GLOB_SH
