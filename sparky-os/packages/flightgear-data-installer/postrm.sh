#!/bin/sh
# postrm script
set -e
# The program is already gone when purge runs, so the purge is written out here: every file and directory this
# package placed is in the lists it kept, and only those are removed.
if [ "$1" = "purge" ]; then
	S=/var/lib/flightgear-data-installer
	for l in files.list pending.files; do
		[ -f "$S/$l" ] || continue
		while IFS= read -r f; do
			rm -f -- "$f"
		done <"$S/$l"
	done
	for l in dirs.list pending.dirs; do
		[ -f "$S/$l" ] || continue
		sort -r "$S/$l" | while IFS= read -r d; do
			rmdir -- "$d" 2>/dev/null || true
		done
	done
	rm -rf "$S" /var/cache/flightgear-data-installer
fi
exit 0
