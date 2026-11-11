#!/bin/bash
# Tests for the missing-or-not-a-regular-file fix (audit U36). Run inside a container that has ffmpeg, with the
# en_US.UTF-8 and de_DE.UTF-8 locales generated:
# the worker is /usr/bin/sparky-audio-convert from the installed .deb (DEB=/path/to/deb installs it first).
set -u
TOOL=/usr/bin/sparky-audio-convert
FAILS=0

ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }

setup() {
	[ -n "${DEB:-}" ] && { dpkg -i "$DEB" >/dev/null 2>&1 || { echo "cannot install $DEB"; exit 99; }; }
	rm -rf /tmp/u36 && mkdir -p /tmp/u36/adir
	ffmpeg -nostdin -loglevel error -f lavfi -i sine=frequency=440:duration=0.5 -y /tmp/u36/real.wav
	export LANG=en_US.UTF-8
}

t_missing_named() {
	local out rc
	out=$("$TOOL" flac /tmp/u36/no-such.wav 2>&1) && rc=0 || rc=$?
	check "missing input is refused" test "$rc" -ne 0
	check "missing input is named" grep -q "Cannot convert no-such.wav" <<<"$out"
	check "rejected run is not said like a conversion" grep -vq "Converted 1 file(s)" <<<"$out"
}

t_directory_named() {
	local out rc
	out=$("$TOOL" flac /tmp/u36/adir 2>&1) && rc=0 || rc=$?
	check "directory is refused" test "$rc" -ne 0
	check "directory is named" grep -q "Cannot convert adir" <<<"$out"
}

t_missing_named_german() {
	local out rc
	out=$(LANG=de_DE.UTF-8 "$TOOL" flac /tmp/u36/no-such.wav 2>&1) && rc=0 || rc=$?
	check "german missing input is refused" test "$rc" -ne 0
	check "german message names the file" grep -q "kann nicht konvertiert werden" <<<"$out"
}

t_happy_unchanged() {
	local out rc
	out=$("$TOOL" flac /tmp/u36/real.wav 2>&1) && rc=0 || rc=$?
	check "normal run is exit 0" test "$rc" -eq 0
	check "normal run converted" test -f /tmp/u36/real.flac
	check "all converted is said as converted" grep -q "Converted 1 file(s) to FLAC" <<<"$out"
}

t_no_input_is_usage() {
	local out rc
	out=$("$TOOL" flac 2>&1) && rc=0 || rc=$?
	check "no input is the usage error" test "$rc" -eq 2
	check "no input prints usage" grep -qi "usage:" <<<"$out"
}

setup
t_missing_named
t_missing_named_german
t_directory_named
t_happy_unchanged
t_no_input_is_usage
[ "$FAILS" -eq 0 ] || { echo "$FAILS test(s) failed"; exit 1; }
echo "all tests passed"
