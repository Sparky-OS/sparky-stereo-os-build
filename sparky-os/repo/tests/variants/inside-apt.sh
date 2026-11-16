#!/bin/sh
# Phase 2 of run.sh, inside a container whose /proc/cpuinfo is a faked processor and whose /work/t holds the trees of phase 1:
# apt (with sparky-stereo-apt's variant files) on the tree named by $1.
set -eu
TREE=$1
cp /apt/62sparky-stereo-variants /etc/apt/apt.conf.d/
install -Dm644 /apt/variants/varianttable /usr/share/sparky-stereo-apt/varianttable
rm -f /etc/apt/sources.list.d/debian.sources
echo "deb [trusted=yes] file:/work/t/$TREE mashtabba main" >/etc/apt/sources.list.d/tree.list
apt-get -q update >/tmp/update.out 2>&1 || { cat /tmp/update.out; exit 2; }
for p in a b c; do
	if apt-get -y install $p >/dev/null 2>&1; then $p; else echo "$p: not installable"; fi
done
