#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# usage: run.sh OUT [RUNS]  - run in a throwaway container started with --ulimit core=1 and on two CPUs (--cpuset-cpus A,B),
# where the libxext6 under test is installed with libxrandr-dev, libx11-dev, gcc and xvfb (queue row 762c).
# The X server: with DISPLAY unset the runner starts its own, Xvfb with -nolisten tcp on the first free display (Xvfb names it
# through -displayfd once it accepts clients), and stops it at the end; with DISPLAY set it uses that server (a session's
# Xwayland). Builds xrr-stress.c (four threads opening, querying RandR on and closing their own X displays at once), runs it RUNS
# times (default 10) under a 120 s guard, writes OUT/runs.tsv (run, exit status, seconds), each run's output, OUT/libxext.txt
# (the installed libxext6 and the sha256 of the libXext.so.6 the program loads) and prints the tally. WRAP, when set, is put
# before each run (valgrind --error-exitcode=99 ...). Exit 0 only when every run finished with status 0.
# Debian's libxext6 2:1.3.4-1+b4 breaks the heap in every run (glibc aborts, status 134, or a crash, 139); with
# patches/libxext-xge-static-extension-record.patch every run finishes. Two CPUs make the race certain; on more it is rarer.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "${1:?output folder}" && cd "$1" && pwd)
N=${2:-10}
B=$(mktemp -d)
gcc -O1 -g -Wall -Wextra -o "$B/xrr-stress" "$HERE/xrr-stress.c" -lXrandr -lX11 -lpthread ||
	{ echo "the stress program did not build" >&2; exit 125; }
# A crash is a status of 128 or more; its core stays inside the container only when the core limit is exactly 1 byte, which the
# container's launcher sets (docker run --ulimit core=1): a piped core_pattern takes 1 as "no dump" and ignores 0. The program
# also marks itself not dumpable, which covers Valgrind (it lowers its own limit to 0 before it re-raises a fatal signal).
core=$(awk '/^Max core file size/ {print $5}' /proc/self/limits)
[ "$core" = 1 ] || { echo "the core limit is $core, not 1 byte: start the container with --ulimit core=1" >&2; exit 125; }
xvfb=
if [ -z "${DISPLAY:-}" ]; then
	Xvfb -displayfd 1 -nolisten tcp -screen 0 1280x720x24 > "$B/display" 2> "$OUT/xvfb.log" &
	xvfb=$!
	for _ in $(seq 100); do [ -s "$B/display" ] && break; sleep 0.1; done
	[ -s "$B/display" ] || { echo "Xvfb did not start: $OUT/xvfb.log" >&2; kill "$xvfb" 2>/dev/null; exit 125; }
	export DISPLAY=:$(tr -d '\n' < "$B/display")
fi
lib=$(ldd "$B/xrr-stress" | awk '$1 == "libXext.so.6" {print $3}')
[ -n "$lib" ] || { echo "the stress program does not load libXext.so.6" >&2; exit 125; }
{
	dpkg-query -W -f '${Package} ${Version} ${Architecture}\n' 'libxext6:*'
	echo "loaded $(readlink -f "$lib") sha256 $(sha256sum < "$(readlink -f "$lib")" | cut -d' ' -f1) from $(dpkg -S "$lib" 2>/dev/null | cut -d: -f1-2)"
	echo "display $DISPLAY${xvfb:+ (Xvfb, started by this runner)} cpus $(nproc)"
} > "$OUT/libxext.txt"
: > "$OUT/runs.tsv"
ok=0
for i in $(seq "$N"); do
	start=$(date +%s.%N)
	XRR_THREADS=4 XRR_ITERS=300 timeout 120 ${WRAP:-} "$B/xrr-stress" > "$OUT/run-$i.txt" 2>&1
	rc=$?
	end=$(date +%s.%N)
	printf '%s\t%s\t%s\n' "$i" "$rc" "$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.2f", b - a }')" >> "$OUT/runs.tsv"
	[ "$rc" = 0 ] && ok=$((ok + 1))
done
[ -z "$xvfb" ] || kill "$xvfb" 2>/dev/null
rm -rf "$B"
echo "runs=$N finished=$ok failed=$((N - ok)) ($(head -1 "$OUT/libxext.txt" | tr '\n' ' ')$(sed -n 's/^loaded \(.*\) sha256 \(.\{12\}\).*/\1 \2/p' "$OUT/libxext.txt"))"
[ "$ok" = "$N" ]
