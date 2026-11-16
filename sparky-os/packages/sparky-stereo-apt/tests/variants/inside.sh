#!/bin/sh
# One case of the variants test, inside a container with no network. Arguments: the toy repository (complete or incomplete), then
# the commands to run; the overlay folders are copied over / by run.sh before this starts.
set -eu
REPO=${1:?repository folder}
printf 'deb [trusted=yes] file:%s toy main\n' "$REPO" >/etc/apt/sources.list.d/toy.list
rm -f /etc/apt/sources.list.d/debian.sources
apt-get -o Debug::NoLocking=1 update >/tmp/update.out 2>&1 || { cat /tmp/update.out; exit 2; }
