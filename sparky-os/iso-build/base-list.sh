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
sort -u "$W/names" > "$W/wanted"
# Names today's Debian testing no longer has (lists/base-gone.tsv: name, tab, what took its place) are not asked for,
# and are checked below: one that has a package again stops the build, so the list cannot hide a package that exists.
GONE=${GONE:-/edition-lists/base-gone.tsv}
[ -r "$GONE" ] || { echo "!! Cannot read $GONE (the base names Debian testing no longer has)." >&2; exit 1; }
awk -F'\t' '!NF || /^#/ { next } { print $1 }' "$GONE" | sort -u > "$W/gone"
awk 'FILENAME == ARGV[1] { gone[$0] = 1; next } !gone[$0] { print }' "$W/gone" "$W/wanted" > "$W/requested"
awk 'FILENAME == ARGV[1] { want[$0] = 1; next } want[$0] { print }' "$W/wanted" "$W/gone" > "$W/gone-asked"
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
	echo "Supply these packages in the configured repositories, or give each a row in lists/base-gone.tsv saying what took its place, and rerun base-list.sh." >&2
	exit 1
fi
if [ -s "$W/gone-asked" ]; then
	set -- $(cat "$W/gone-asked")
	apt-cache policy "$@" > "$W/gone-policy" || {
		echo "!! Could not query APT candidates for the names in base-gone.tsv. Repair APT metadata and rerun base-list.sh." >&2
		exit 1
	}
	awk '
/^[^ ].*:$/ { p = substr($1, 1, length($1)-1) }
/Candidate:/ && $2 != "(none)" { print p }
' "$W/gone-policy" > "$W/back"
	if [ -s "$W/back" ]; then
		echo "!! Listed in base-gone.tsv as gone, but apt has a package for them again:" >&2
		cat "$W/back" >&2
		echo "Remove their rows from lists/base-gone.tsv and rerun base-list.sh." >&2
		exit 1
	fi
fi
cat "$W/requested"
