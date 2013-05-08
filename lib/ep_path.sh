#
# Assertion path handling
#
# Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.

if [ -z ${_EP_PATH_SH+set} ]; then
declare -r _EP_PATH_SH=

. ep_glob.sh

# Match an assertion path against a negative pattern.
# Args: pattern path
function ep_path_match_negative()
{
    declare -r pattern="$1"
    declare -r path="$2"

    # If it's the exact node
    if ep_glob_aborting "$pattern" "$path" ||
       # Or a child
       ep_glob_aborting --text-prefix "$pattern/" "$path"; then
        return 0
    else
        return 1
    fi
}

# Match either a final or a partial assertion path against a positive pattern.
# Args: pattern path final
function ep_path_match_positive()
{
    declare -r pattern="$1"
    declare -r path="$2"
    declare -r final="$3"

    # If it's a possible parent
    if ! $final &&
       ep_glob_aborting --pattern-prefix "$pattern" "$path/" ||
       # Or the exact node
       ep_glob_aborting "$pattern" "$path" ||
       # Or a child
       ep_glob_aborting --text-prefix "$pattern/" "$path"; then
        return 0
    else
        return 1
    fi
}

# Match either a final or a partial assertion path against a filter - a pair
# of optional pattern variables - one that should match and one that
# shouldn't.
# Args: path final filter default
#
# The logic table is this:
#
#   INCLUDE     EXCLUDE     RESULT
#   -           -           D
#   -           N           Y
#   -           Y           N
#   N           -           N
#   N           N           N
#   N           Y           N
#   Y           -           Y
#   Y           N           Y
#   Y           Y           N
#
#   - - unset
#   Y - match
#   N - mismatch
#   D - default
#
function ep_path_filter()
{
    declare -r path="$1"
    declare -r final="$2"
    declare -r filter="$3"
    declare -r default="$4"

    declare -r include_var="EP_$filter"
    declare -r exclude_var="EP_DONT_$filter"
    declare include_set
    declare exclude_set
    declare include
    declare exclude
    declare match

    # If include variable is specified
    if [ -n "${!include_var+set}" ]; then
        include_set=true
        ep_path_match_positive "${!include_var}" "$path" "$final" &&
            include=1 || include=0
    else
        include_set=false
    fi

    # If exclude variable is specified
    if [ -n "${!exclude_var+set}" ]; then
        exclude_set=true
        ep_path_match_negative "${!exclude_var}" "$path" &&
            exclude=1 || exclude=0
    else
        exclude_set=false
    fi

    # Combine matching results
    if $include_set; then
        if $exclude_set; then
            match=$((include && !exclude))
        else
            match=$((include))
        fi
    elif $exclude_set; then
        match=$((!exclude))
    else
        $default && match=1 || match=0
    fi

    return $((!match))
}

fi # _EP_PATH_SH
