#!/bin/sh
# The loading screen shows the boot splash's picture (ORDER 571): its pictures are sparky-stereo-plymouth's, byte for byte, and
# Splash.qml places them with the factors gen-theme.py writes into the boot splash's script. Fails on the first difference.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
P=$HERE/../sparky-stereo-plymouth
fail=0
for f in background.png logo.png electron.png; do
	cmp -s "$HERE/retained-splash/splash/images/$f" "$P/upstream/sparky-lines/$f" || { echo "not the boot splash's picture: $f"; fail=1; }
done
cmp -s "$HERE/retained-splash/splash/images/wordmark.png" "$P/art/wordmark.png" || { echo "not the boot splash's picture: wordmark.png"; fail=1; }
for k in 0.7 0.092 0.4245 0.611 0.295 0.3303 0.3825 0.411 0.2248 0.1645 0.7065 0.460 0.2945 0.2343 0.06 0.6; do
	grep -q -- "$k" "$P/gen-theme.py" && grep -q -- "$k" "$HERE/retained-splash/splash/Splash.qml" || { echo "a factor of the boot splash's placement is missing: $k"; fail=1; }
done
[ "$fail" = 0 ] && echo "the retained loading screen pictures and placement are the boot splash ones"
exit "$fail"
