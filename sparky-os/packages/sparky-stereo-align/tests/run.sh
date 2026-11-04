#!/bin/bash
# Tests for the check-every-input-before-deciding fix (audit U44). Run inside a container that has python3-pil and
# hugin-tools, with the en_US.UTF-8 and de_DE.UTF-8 locales generated:
# the worker is /usr/lib/sparky-stereo/align/align from the installed .deb (DEB=/path/to/deb installs it first).
set -u
TOOL=/usr/lib/sparky-stereo/align/align
FAILS=0

ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }

setup() {
	[ -n "${DEB:-}" ] && { dpkg -i "$DEB" >/dev/null 2>&1 || { echo "cannot install $DEB"; exit 99; }; }
	rm -rf /tmp/u44 && mkdir -p /tmp/u44/adir
	python3 - <<'PY'
from PIL import Image, ImageDraw
img = Image.new('RGB', (512, 512), (210, 210, 210))
d = ImageDraw.Draw(img)
for i, colour in enumerate([(200, 30, 30), (30, 200, 30), (30, 30, 200), (200, 200, 30), (30, 200, 200)]):
    for j, shape in enumerate(['ellipse', 'rectangle']):
        x, y = 20 + (i * 5 + j) % 5 * 100, 20 + ((i * 5 + j) // 5) * 140
        getattr(d, shape)([x, y, x + 60, y + 60], fill=colour)
img.save('/tmp/u44/base.png')
img.transform((512, 512), Image.AFFINE, (1, 0, 5, 0, 1, -4)).save('/tmp/u44/pair-right.png')
PY
	export LANG=en_US.UTF-8
}

t_pair_with_missing_eye() {
	local out rc
	out=$("$TOOL" pns -- /tmp/u44/base.png /tmp/u44/no-right.png 2>&1) && rc=0 || rc=$?
	check "pair with a missing eye is refused" test "$rc" -ne 0
	check "missing eye is named" grep -q "Cannot align /tmp/u44/no-right.png" <<<"$out"
	check "pair is not reinterpreted as one picture" bash -c '! grep -q "is not a stereo picture" <<<"$0"' "$out"
	check "no aligned file was written" bash -c '! ls /tmp/u44/base-aligned.pns >/dev/null 2>&1'
}

t_both_missing_named() {
	local out rc
	out=$("$TOOL" pns -- /tmp/u44/no-left.png /tmp/u44/no-right.png 2>&1) && rc=0 || rc=$?
	check "two missing are refused" test "$rc" -ne 0
	check "both are named" bash -c 'grep -q "no-left.png" <<<"$0" && grep -q "no-right.png" <<<"$0"' "$out"
}

t_directory_named() {
	local out rc
	out=$("$TOOL" pns -- /tmp/u44/base.png /tmp/u44/adir 2>&1) && rc=0 || rc=$?
	check "directory is refused" test "$rc" -ne 0
	check "directory is named" grep -q "Cannot align /tmp/u44/adir" <<<"$out"
}

t_missing_named_german() {
	local out rc
	out=$(LANG=de_DE.UTF-8 "$TOOL" pns -- /tmp/u44/base.png /tmp/u44/no-right.png 2>&1) && rc=0 || rc=$?
	check "german missing input is refused" test "$rc" -ne 0
	check "german message names the file" grep -q "kann nicht ausgerichtet werden" <<<"$out"
}

t_happy_unchanged() {
	local out rc
	out=$("$TOOL" pns -- /tmp/u44/base.png /tmp/u44/pair-right.png 2>&1) && rc=0 || rc=$?
	check "normal run is exit 0" test "$rc" -eq 0
	check "normal run wrote the aligned file" test -f /tmp/u44/base-aligned.pns
}

setup
t_pair_with_missing_eye
t_both_missing_named
t_directory_named
t_missing_named_german
t_happy_unchanged
[ "$FAILS" -eq 0 ] || { echo "$FAILS test(s) failed"; exit 1; }
echo "all tests passed"
