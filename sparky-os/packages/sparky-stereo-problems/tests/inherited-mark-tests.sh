#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Run as root in a throwaway systemd container with the engine installed.
set -u
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=$((fail + 1)); fi; }
B=/usr/bin/sparky-stereo-problems
P=sparky-stereo-problems
W=$(mktemp -d)
trap 'rm -r "$W"' EXIT
mkdir -p "$W/package/DEBIAN"
cat >"$W/package/DEBIAN/control" <<'EOS'
Package: problems-inherited-mark-test
Version: 1
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Description: disposable inherited environment reproduction
EOS
cat >"$W/package/DEBIAN/postinst" <<'EOS'
#!/bin/sh
sparky-stereo-problems run --machine sparky-stereo-problems inherited-run LOCAL34 @LOCAL35 -- touch /run/problems-inherited-command-ran || :
EOS
chmod 755 "$W/package/DEBIAN/postinst"
dpkg-deb --build "$W/package" "$W/test.deb" >/dev/null
rm -f /run/problems-inherited-command-ran
# The parent of dpkg, its postinst and the command all carry the same mark.
env PKEXEC_UID=1000 dpkg -i "$W/test.deb" >"$W/install.log" 2>&1; rc=$?
cat "$W/install.log"
check 'dpkg and its post-invoke hook pass with the inherited mark' '[ "$rc" = 0 ]'
check 'the maintainer command really ran, even though its script ignores failure' '[ -f /run/problems-inherited-command-ran ]'
env PKEXEC_UID=1000 "$B" keep --machine "$P" inherited-keep LOCAL4 >"$W/keep.log" 2>&1; rc=$?
cat "$W/keep.log"
check 'keep works with the parent mark' '[ "$rc" = 0 ] && [ -f /var/lib/sparky-stereo-problems/sparky-stereo-problems_inherited-keep.json ]'
"$B" keep --machine "$P" inherited-clear LOCAL4 >/dev/null 2>&1
env PKEXEC_UID=1000 "$B" clear --machine "$P" inherited-clear >"$W/clear.log" 2>&1; rc=$?
check 'clear works with the parent mark' '[ "$rc" = 0 ] && [ ! -e /var/lib/sparky-stereo-problems/sparky-stereo-problems_inherited-clear.json ]'
env PKEXEC_UID=1000 "$B" list --json >"$W/list.json" 2>"$W/list.err"; rc=$?
check 'list works with the parent mark' '[ "$rc" = 0 ] && python3 -m json.tool "$W/list.json" >/dev/null'
"$B" clear --machine "$P" inherited-keep >/dev/null 2>&1
"$B" clear --machine "$P" inherited-clear >/dev/null 2>&1
dpkg -r problems-inherited-mark-test >/dev/null 2>&1
rm -f /run/problems-inherited-command-ran
echo "RESULT: $fail failed"
exit "$fail"
