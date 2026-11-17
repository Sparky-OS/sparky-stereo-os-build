#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# carried-present.sh SOURCE_DIR [PATCH...]: is each carried fix in a kernel source tree? (ORDER 636)
#
# For every patch (default: the files of series group 47, the security fixes no 7.3.y release has), "present" when the patch
# applies in reverse on SOURCE_DIR (its change is there), "MISSING" when it applies forward (its change is not), "UNCLEAR"
# when neither (the tree has other code there). Reads the tree only (git apply --check), builds nothing.
# Red: a pristine release tree says MISSING for each; green: the edition's tree says present for each.
# Exit status: 0 every patch present, 1 any missing or unclear, 2 usage.
set -eu
SRC=${1:?usage: carried-present.sh SOURCE_DIR [PATCH...]}
shift
HERE=$(cd "$(dirname "$0")/../../series" && pwd)
[ "$#" -gt 0 ] || set -- "$HERE"/47-security-beyond-7.3.4/*.patch
bad=0
for p in "$@"; do
    name=$(basename "$p")
    if (cd "$SRC" && git apply --check -R "$p") 2>/dev/null; then
        echo "present  $name"
    elif (cd "$SRC" && git apply --check "$p") 2>/dev/null; then
        echo "MISSING  $name"; bad=$((bad + 1))
    else
        echo "UNCLEAR  $name"; bad=$((bad + 1))
    fi
done
echo "carried-present: $bad of $# not present in $SRC"
[ "$bad" -eq 0 ]
