#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The red controls: each mutation breaks one rule of the installer, the watcher or the launcher in a throwaway copy, and the test that guards the rule must fail.
# In a container with the package folder at /pkg (ro) and the helpers at /tb (dev-install.sh), as tests/installer.sh needs. Usage: mutations.sh NAME FIXTURE_DIR
#   no-verify      the downloaded file is not checked against the reviewed size and SHA-256
#   no-restore     a failed switch does not put the replaced folder back
#   drops-originals the merged certificate list starts empty instead of from the program's own
#   no-previous    the update switches without keeping the previous version's folder
#   watcher-one-fetch the watcher fetches once and compares nothing
#   launcher-no-lock the launcher starts without the lock
set -u
NAME=${1:?}; FX=${2:?}
[ "$NAME" = launcher-no-lock ] || sh /tb/dev-install.sh
LIB=/usr/lib/sparky-pjeoffice/sparky_pjeoffice.py
case $NAME in
no-verify) sed -i 's/^    size = os.path.getsize(path)$/    return\n    size = os.path.getsize(path)/' $LIB; TEST="bash /pkg/tests/installer.sh $FX" ;;
no-restore) sed -i "s/                    os.rename(aside, target)/                    pass/" $LIB; TEST="bash /pkg/tests/installer.sh $FX" ;;
drops-originals) sed -i "s/^var store = load(original);$/var store = KeyStore.getInstance(type); store.load(null, password);/" /usr/lib/sparky-pjeoffice/merge-trust.js; sed -i "s/^var before = encodings(store);$/var before = {set: {}, count: 0}; var loaded = encodings(load(original));/" /usr/lib/sparky-pjeoffice/merge-trust.js; TEST="bash /pkg/tests/installer.sh $FX" ;;
no-previous) sed -i "s/^        keep_set = {version} | .*$/        keep_set = {version}/" $LIB; TEST="bash /pkg/tests/installer.sh $FX" ;;
watcher-one-fetch) cp /pkg/watcher/watch.py /tmp/watch-mutated.py; sed -i "s/    if first\[1\] != second\[1\] or first\[2\] != second\[2\]:/    if False:/" /tmp/watch-mutated.py; TEST="python3 /pkg/watcher/test_watch.py $FX /tmp/watch-mutated.py" ;;
launcher-no-lock) cp /pkg/sh/pjeoffice-pro /tmp/launcher-nolock; sed -i 's/^flock -w 120 9 .*$/true/' /tmp/launcher-nolock; chmod +x /tmp/launcher-nolock; TEST="bash /pkg/tests/rig/twostarts.sh /tmp/launcher-nolock $FX" ;;
*) echo "unknown mutation $NAME"; exit 2 ;;
esac
$TEST > $FX/mutation-$NAME.txt 2>&1; RC=$?
echo "mutation $NAME: test exit $RC"; grep -E "^FAIL" $FX/mutation-$NAME.txt | head -8
[ $RC != 0 ] && echo "RED as expected: $NAME" || { echo "NOT RED: $NAME passed with the rule broken"; exit 1; }
