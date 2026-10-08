# Shared by sparky-stereo-ffmpeg-fdk and its apt hook (sourced, never run).
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/08

STATE=${SPARKY_FDK_STATE:-/var/lib/sparky-stereo-ffmpeg-fdk}
PINFILE=${SPARKY_FDK_PINFILE:-/etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk}
LOG=${SPARKY_FDK_LOG:-/var/log/sparky-stereo-ffmpeg-fdk.log}
LOCK=${SPARKY_FDK_LOCK:-/run/sparky-stereo-ffmpeg-fdk.lock}
LIBDIR=${SPARKY_FDK_LIBDIR:-/usr/lib/sparky-stereo-ffmpeg-fdk}
LANGDIR=${SPARKY_FDK_LANGDIR:-/usr/share/sparky/sparky-stereo-ffmpeg-fdk}
SRCPKG=${SPARKY_FDK_SOURCE:-ffmpeg-dmo}          # our source package: deb-multimedia's ffmpeg-dmo plus the stereo patches
ORIGIN=${SPARKY_FDK_ORIGIN:-Sparky Stereo OS}    # the Origin of the edition's repository
PROFILE=pkg.ffmpeg-dmo.fdk                        # the build profile that turns --enable-libfdk-aac and --enable-nonfree on
# What the build costs in CPU time, measured on the container build of ffmpeg-dmo 10:9.0.2 (user plus system, minutes);
# the time shown to the user is this divided by the processor cores, with room for the downloads and the packaging.
CPU_MINUTES=${SPARKY_FDK_CPU_MINUTES:-@CPU_MINUTES@}

# The strings: the whole LANG=xx_YY, then xx, then English.
load_strings() {
	local code=${LANG%%.*} c
	case "$code" in "" | C | POSIX)
		code=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"' | cut -d. -f1) ;;
	esac
	[ -d "$LANGDIR" ] || LANGDIR=$(dirname "${BASH_SOURCE[0]}")/../lang
	for c in en "$code" "${code%%_*}"; do
		[ -n "$c" ] && [ -f "$LANGDIR/$c" ] && . "$LANGDIR/$c"
	done
	# Portuguese from Portugal and the other pt locales read the Brazilian text, the only Portuguese one there is
	case "$code" in pt_BR) ;; pt | pt_*) [ -f "$LANGDIR/pt_BR" ] && . "$LANGDIR/pt_BR" ;; esac
}

# The highest version of our source package in the edition's own Sources index, and the binary packages it builds:
# "VERSION BINARY,BINARY,...". Nothing when the repository publishes no source index for it.
repo_source() {
	local f
	apt-get indextargets --format '$(FILENAME)' "Origin: $ORIGIN" 'Created-By: Sources' 2>/dev/null |
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			/usr/lib/apt/apt-helper cat-file "$f" 2>/dev/null
			echo
		done | SRCPKG="$SRCPKG" python3 -c '
import os, subprocess, sys
want = os.environ["SRCPKG"]
best = None
for st in sys.stdin.read().split("\n\n"):
    f = {}
    key = None
    for line in st.split("\n"):
        if line[:1] in (" ", "\t") and key:
            f[key] += " " + line.strip()
        elif ":" in line:
            key, val = line.split(":", 1)
            f[key] = val.strip()
    if f.get("Package") != want or not f.get("Version"):
        continue
    if best is None or subprocess.run(["dpkg", "--compare-versions", f["Version"], "gt", best[0]]).returncode == 0:
        best = (f["Version"], f.get("Binary", ""))
if best:
    print(best[0], ",".join(x.strip() for x in best[1].split(",") if x.strip()))
'
}

# The local build installed now: sets LOCAL_BASE (the edition's version it was built from), LOCAL_VERSION, LOCAL_USER (who
# built it) and LOCAL_PACKAGES; returns 1 when there is none.
read_installed() {
	LOCAL_BASE= LOCAL_VERSION= LOCAL_USER= LOCAL_PACKAGES= BUILT_AT=
	[ -s "$STATE/installed" ] || return 1
	# shellcheck disable=SC1091
	. "$STATE/installed"
	[ -n "$LOCAL_BASE" ]
}

# The version of the next local build of the edition's version $1: VERSION+fdkN, N counting up for the same version.
next_local_version() {
	local base=$1 n=0
	if read_installed && [ "$LOCAL_BASE" = "$base" ]; then
		n=${LOCAL_VERSION##*"$SUFFIX_FDK"}
		case "$n" in '' | *[!0-9]*) n=0 ;; esac
	fi
	echo "${base}${SUFFIX_FDK}$((n + 1))"
}
SUFFIX_FDK=+fdk

# The packages of our source that are installed now, "name:arch name:arch ..." (only those of the binary list $1, "a,b,c").
installed_of() {
	local list=",$1,"
	dpkg-query -W -f='${Package} ${Architecture} ${db:Status-Abbrev}\n' 2>/dev/null |
		while read -r name arch st; do
			case "$list" in *",$name,"*) ;; *) continue ;; esac
			case "$st" in ii*) echo "$name:$arch" ;; esac
		done
}

# The pin that makes apt keep the local build: the exact version just installed, above the edition's repository (1001), for
# each installed package of the build with its architecture (a name alone covers the native architecture only, so the 32-bit
# twin would be put back). apt's version pin takes an exact version or a prefix that ends in "*" and nothing else: a "*" at
# the start is accepted without a warning and matches nothing, which is why the file is written here, for the version of each
# build, and not shipped with a pattern in it.
write_pin() {
	local names tmp rc
	read_installed || return 1
	names=$(for tmp in $LOCAL_PACKAGES; do echo "${tmp%:all}"; done | sort -u | tr '\n' ' ')
	names=${names% }
	[ -n "$names" ] || return 1
	tmp=$(mktemp "$STATE/pin.XXXXXX") || return 1
	{
		printf '# Written by sparky-stereo-ffmpeg-fdk, which owns this file: the FFmpeg built on this computer, kept by apt.\n'
		printf '# It goes away with "sparky-stereo-ffmpeg-fdk --remove" and with the removal of the package.\n'
		printf 'Package: %s\nPin: version %s\nPin-Priority: 1002\n' "$names" "$LOCAL_VERSION"
	} >"$tmp" && install -m 644 "$tmp" "$PINFILE"
	rc=$?
	rm -f -- "$tmp"
	return $rc
}

drop_pin() {
	rm -f -- "$PINFILE"
}
