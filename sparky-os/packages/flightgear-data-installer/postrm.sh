#!/bin/sh
# postrm script
set -e
# The data leaves with the package, on remove as well as on purge, as Debian's data packages and
# ttf-mscorefonts-installer do (ORDER 399b): every file and directory this package placed is in the lists it kept, and
# only those are removed, with what was downloaded. The program is already gone by now, so this is written out here.
# An upgrade (postrm upgrade of the old version) leaves the data where it is.
# ORDER 645: a listed path is removed only when the folder that holds it, with every link followed, is still under the data
# folder; a path that goes out through a link (Timezone -> ../../zoneinfo) is left alone and said, never followed.
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	D=/usr/share/games/flightgear
	S=/var/lib/flightgear-data-installer
	inside() {
		real=$(realpath -m -- "$D") || return 1
		parent=$(realpath -m -- "$(dirname -- "$1")") || return 1
		case $parent/ in
			"$real"/*) return 0 ;;
		esac
		case $1 in
			"$D" | "$(dirname -- "$D")") return 0 ;;
		esac
		return 1
	}
	left_alone() {
		echo "flightgear-data-installer: $1 is not inside FlightGear's data folder as it stands (a link leads out of it), so it was left alone." >&2
	}
	for l in files.list pending.files; do
		[ -f "$S/$l" ] || continue
		while IFS= read -r f; do
			if inside "$f"; then rm -f -- "$f"; else left_alone "$f"; fi
		done <"$S/$l"
	done
	for l in dirs.list pending.dirs shared.list pending.shared; do
		[ -f "$S/$l" ] || continue
		sort -r "$S/$l" | while IFS= read -r d; do
			if inside "$d"; then rmdir -- "$d" 2>/dev/null || true; else left_alone "$d"; fi
		done
	done
	# the state and the download cache: rm says by itself what it could not remove (a folder that is a mount point, for one), and the
	# removal of the package goes on, since the data it placed is already gone
	rm -rf "$S" /var/cache/flightgear-data-installer || true
	# a problem this package kept is over with it (its repair is the program that is gone by now)
	if command -v sparky-stereo-problems >/dev/null 2>&1; then
		sparky-stereo-problems clear --all flightgear-data-installer >/dev/null 2>&1 || true
	fi
fi
exit 0
