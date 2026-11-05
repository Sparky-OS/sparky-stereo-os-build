#!/bin/bash
# Tests for the missing-or-not-a-regular-file fix (audit U35). Run inside a container that has mkvtoolnix and ffmpeg,
# with the en_US.UTF-8 and de_DE.UTF-8 locales generated (mkvtoolnix aborts under a LANG that is not generated):
# the worker is /usr/lib/sparky-stereo/mkv-mark/mark from the installed .deb (DEB=/path/to/deb installs it first).
set -u
TOOL=/usr/lib/sparky-stereo/mkv-mark/mark
FAILS=0

ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }

setup() {
	[ -n "${DEB:-}" ] && { dpkg -i "$DEB" >/dev/null 2>&1 || { echo "cannot install $DEB"; exit 99; }; }
	rm -rf /tmp/u35 && mkdir -p /tmp/u35/adir
	ffmpeg -nostdin -loglevel error -f lavfi -i color=c=black:s=64x64:d=1 -c:v libx264 -y /tmp/u35/real.mkv
	export LANG=en_US.UTF-8
}

t_missing_named() {
	local out rc
	out=$("$TOOL" 1 -- /tmp/u35/no-such.mkv 2>&1) && rc=0 || rc=$?
	check "missing input is refused" test "$rc" -ne 0
	check "missing input is named" grep -q "Cannot mark no-such.mkv" <<<"$out"
}

t_directory_named() {
	local out rc
	out=$("$TOOL" 1 -- /tmp/u35/adir 2>&1) && rc=0 || rc=$?
	check "directory is refused" test "$rc" -ne 0
	check "directory is named" grep -q "Cannot mark adir" <<<"$out"
}

t_mixed_counts_the_missing() {
	local out rc
	out=$("$TOOL" 1 -- /tmp/u35/real.mkv /tmp/u35/no-such.mkv 2>&1) && rc=0 || rc=$?
	check "mixed run fails overall" test "$rc" -ne 0
	check "mixed run names the missing file" grep -q "Cannot mark no-such.mkv" <<<"$out"
}

t_missing_named_german() {
	local out rc
	out=$(LANG=de_DE.UTF-8 "$TOOL" 1 -- /tmp/u35/no-such.mkv 2>&1) && rc=0 || rc=$?
	check "german missing input is refused" test "$rc" -ne 0
	check "german message names the file" grep -q "kann nicht markiert werden" <<<"$out"
}

t_happy_unchanged() {
	local out rc
	out=$("$TOOL" 1 -- /tmp/u35/real.mkv 2>&1) && rc=0 || rc=$?
	check "normal run is exit 0" test "$rc" -eq 0
	check "normal run says it marked" grep -q "Marked 1 file(s)" <<<"$out"
}

setup
t_missing_named
t_missing_named_german
t_directory_named
t_happy_unchanged
t_mixed_counts_the_missing
[ "$FAILS" -eq 0 ] || { echo "$FAILS test(s) failed"; exit 1; }
echo "all tests passed"
