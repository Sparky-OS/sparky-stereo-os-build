#!/bin/bash
# usage: aptdl.sh <dir> pkg=ver...  (as user, state under /o/aptstate)
set -e
mkdir -p /o/aptstate/lists/partial /o/aptstate/cache/archives/partial
cat > /o/aptstate/sources.list <<L
deb http://deb.debian.org/debian testing main
L
O="-o Dir::Etc::sourcelist=/o/aptstate/sources.list -o Dir::Etc::sourceparts=/dev/null -o Dir::State::lists=/o/aptstate/lists -o Dir::Cache=/o/aptstate/cache -o Dir::State::status=/var/lib/dpkg/status -o Debug::NoLocking=1"
apt-get $O update -qq
d=$1; shift; mkdir -p $d; cd $d
for p in "$@"; do apt-get $O download $p; done
apt-cache $O policy kalzium libavogadro2-1t64 | head -12
