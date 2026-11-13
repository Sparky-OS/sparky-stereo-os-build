#!/bin/bash
# Sparky Stereo OS: the libraries' names made by this build must be the names the source's control file was written
# for. They carry the compiler and every crate, version, source and feature: another compiler or another resolve gives
# other names, and then the source is made again, never renamed here.
set -euo pipefail
ws=$1; names=$2; bad=0
while read -r key soname; do
	[ "$key" != rustc ] || continue
	dir=$ws/$( [ "$key" = craft-suite ] && echo shared || echo "$key-shared" )
	built=$(cat "$dir/soname.txt")
	if [ "$built" != "$soname" ]; then
		echo "$key: this build names its library $built, the source was made for $soname" >&2
		bad=1
	fi
done <"$names"
if [ "$bad" = 1 ]; then
	echo "the source was made with rustc $(awk '$1=="rustc"{print $2}' "$names"); this build has rustc $(dpkg-query -W -f '${Version}' rustc). Make the source again with this compiler (build.sh) so the package names follow the libraries." >&2
	exit 1
fi
echo "the libraries' names equal the source's: $(grep -vc '^rustc ' "$names") libraries"
