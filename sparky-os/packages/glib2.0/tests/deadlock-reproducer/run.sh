#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# usage: run.sh OUT [RUNS]  - run in a throwaway container where the GLib under test is installed with libglib2.0-dev,
# pkgconf and gcc at the same version (ORDER 768).
# Builds repro.c (what geoclue 2.8.2 does at start: can_reach_async(), then g_file_new_for_path() on the main thread) and
# slowproxy.c (a proxy resolver module that makes a GFile while GIO holds default_modules_lock, as libproxy's
# config-sysconfig plugin does), runs repro RUNS times (default 10) under a 20 s guard, writes OUT/runs.tsv (run, exit
# status, seconds) and each run's output, and prints the tally. Exit 0 only when every run finished with status 0.
# Debian's 2.90.1-2 hangs every time (exit 124 from the guard); with upstream's commit 4301b49671 every run finishes.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "${1:?output folder}" && cd "$1" && pwd)
N=${2:-10}
B=$(mktemp -d)
mkdir -p "$B/modules"
gcc -Wall -Wextra -o "$B/repro" "$HERE/repro.c" $(pkg-config --cflags --libs gio-2.0) &&
	gcc -Wall -Wextra -shared -fPIC -o "$B/modules/libg768slowproxy.so" "$HERE/slowproxy.c" $(pkg-config --cflags --libs gio-2.0) ||
	{ echo "the reproducer did not build" >&2; exit 125; }
dpkg-query -W -f '${Package} ${Version} ${Architecture}\n' 'libglib2.0-0t64*' > "$OUT/glib.txt"
ulimit -c 0
: > "$OUT/runs.tsv"
ok=0
for i in $(seq "$N"); do
	start=$(date +%s.%N)
	GIO_EXTRA_MODULES="$B/modules" GIO_USE_PROXY_RESOLVER=g768-slow GIO_USE_NETWORK_MONITOR=netlink GIO_USE_VFS=local \
		timeout 20 "$B/repro" > "$OUT/run-$i.txt" 2>&1
	rc=$?
	end=$(date +%s.%N)
	printf '%s\t%s\t%s\n' "$i" "$rc" "$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.2f", b - a }')" >> "$OUT/runs.tsv"
	[ "$rc" = 0 ] && ok=$((ok + 1))
done
rm -rf "$B"
echo "runs=$N finished=$ok hung_or_failed=$((N - ok)) ($(cat "$OUT/glib.txt" | tr '\n' ' '))"
[ "$ok" = "$N" ]
