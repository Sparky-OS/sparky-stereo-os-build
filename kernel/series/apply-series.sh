#!/bin/sh
# apply-series.sh SOURCE_DIR [FLAVOUR]
#
# Applies the patch series of this directory to an unpacked vanilla kernel tree (v7.3-rc6 or later), in the
# order of series.txt, then series-FLAVOUR.txt if FLAVOUR is given (v3 adds one patch, rt adds none; every flavour has a list).
# Works on a plain tree (no .git needed): every file is applied with `git apply`, which is atomic per file.
#
# Environment:
#   SKIP   extended regex; series lines that match it are not applied (example: SKIP='^(16-|26-)' drops the
#          aw87xxx audio group and the POC selector)
#   CHECK  set to 1 to only test that every file applies (still applies them in order; use a scratch copy)
#
# Exit status: 0 all applied, 1 a file failed (its name is printed and nothing after it was applied).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?usage: apply-series.sh SOURCE_DIR [FLAVOUR]}
FLAVOUR=${2:-}
SKIP=${SKIP:-}
n=0; skipped=0
apply_list() {
    list=$1
    [ -f "$list" ] || { echo "apply-series: no such list $list" >&2; exit 1; }
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue;; esac
        if [ -n "$SKIP" ] && printf '%s\n' "$line" | grep -Eq "$SKIP"; then
            skipped=$((skipped+1)); continue
        fi
        if ! (cd "$SRC" && git apply --whitespace=nowarn "$HERE/$line") 2>/tmp/apply-series.err.$$; then
            echo "apply-series: FAILED $line" >&2
            cat /tmp/apply-series.err.$$ >&2; rm -f /tmp/apply-series.err.$$
            exit 1
        fi
        n=$((n+1))
    done < "$list"
}
apply_list "$HERE/series.txt"
if [ -n "$FLAVOUR" ] && [ "$FLAVOUR" != base ]; then
    apply_list "$HERE/series-$FLAVOUR.txt"
fi
rm -f /tmp/apply-series.err.$$
echo "apply-series: $n patch files applied, $skipped skipped${FLAVOUR:+ (flavour $FLAVOUR)}"
