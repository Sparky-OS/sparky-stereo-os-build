#!/bin/sh
# Prints the selected Sparky KDE base packages only after every name has an APT candidate.
# Libraries, Debian kernels and the explicit edition removals retain their existing policy.
set -eu
export LC_ALL=C
W=$(mktemp -d "${TMPDIR:-/tmp}/base-list.XXXXXX")
trap 'rm -rf "$W"' EXIT
awk '
FILENAME == ARGV[1] { removed[$0] = 1; next }
/^lib/ && !/^libr/ && $0 != "libdvdcss2" && $0 != "libasound2-plugins" { next }
/^(linux-image-[0-9]|linux-headers-[0-9]|linux-base-|linux-binary-|linux-modules-|linux-(image|headers|signed)-.*amd64$)/ { next }
!NF || /^#/ || removed[$0] { next }
{ print }
' "${REMOVE:-/edition-lists/base-remove.list}" "${NAMES:-/build/sparky-kde-2026.09.names}" > "$W/names"
sort -u "$W/names" > "$W/requested"
[ -s "$W/requested" ] || { echo "!! Base package selection is empty; check NAMES and REMOVE." >&2; exit 1; }
# Package names are one per line; disable globbing before forming APT arguments.
set -f
set -- $(cat "$W/requested")
apt-cache policy "$@" > "$W/policy" || {
	echo "!! Could not query APT candidates for the base image. Repair APT metadata and rerun base-list.sh." >&2
	exit 1
}
awk '
/^[^ ].*:$/ { p = substr($1, 1, length($1)-1) }
/Candidate:/ && $2 != "(none)" { print p }
' "$W/policy" > "$W/candidates"
# Check every requested identity, not just the records APT happened to return.
awk 'FILENAME == ARGV[1] { found[$0] = 1; next } !found[$0] { print }' \
	"$W/candidates" "$W/requested" > "$W/missing"
if [ -s "$W/missing" ]; then
	echo "!! Base image packages unavailable:" >&2
	cat "$W/missing" >&2
	echo "Supply these packages in the configured repositories and rerun base-list.sh." >&2
	exit 1
fi
cat "$W/requested"
