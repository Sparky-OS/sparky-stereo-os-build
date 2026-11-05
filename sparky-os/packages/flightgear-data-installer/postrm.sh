#!/bin/sh
# postrm script
set -e
# The data leaves with the package, on remove as well as on purge, as Debian's data packages and
# ttf-mscorefonts-installer do (ORDER 399b): every file and directory this package placed is in the lists it kept, and
# only those are removed, with what was downloaded. The program is already gone by now, so this is written out here.
# An upgrade (postrm upgrade of the old version) leaves the data where it is.
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	S=/var/lib/flightgear-data-installer
	for l in files.list pending.files; do
		[ -f "$S/$l" ] || continue
		while IFS= read -r f; do
			rm -f -- "$f"
		done <"$S/$l"
	done
	for l in dirs.list pending.dirs shared.list pending.shared; do
		[ -f "$S/$l" ] || continue
		sort -r "$S/$l" | while IFS= read -r d; do
			rmdir -- "$d" 2>/dev/null || true
		done
	done
	# the state and the download cache: rm says by itself what it could not remove (a folder that is a mount point, for one), and the
	# removal of the package goes on, since the data it placed is already gone
	rm -rf "$S" /var/cache/flightgear-data-installer || true
fi
exit 0
