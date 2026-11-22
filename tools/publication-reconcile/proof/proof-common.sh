# ORDER 384 (310 proof-common.sh, with the whole pin directory copied; Opus 2026-11-04: the image's debconf answers and grub stubs): sourced inside each fresh container (root, its own APT state).
# file: source, either /base (the copy equal to the live tree, official key) or /cand (the candidate, throwaway key).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
unset OPENSSL_CONF OPENSSL_MODULES
O=/out; mkdir -p $O
PASSED=0
pass() { echo "PASS $*" | tee -a $O/checks.txt; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL $*" | tee -a $O/checks.txt; echo "FAIL $*" >$O/verdict.txt; exit 1; }
# sparky-stereo-apt and sparky-apt (pulled by sparky-stereo-ffmpeg-fdk) ship conffiles at the paths of the sources
# and pin written here; keep these (--force-confold), so the edition source stays the copy under test
apt_get() { apt-get -o APT::Update::Error-Mode=any -o Dpkg::Use-Pty=0 -o APT::Color=0 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
setup_sources() {
	# sparky-stereo-apt (a dependency of sparky-stereo-ffmpeg-fdk) ships /etc/apt/sources.list.d/sparky-stereo.sources
	# pointing at https://repo.sparkyos.org, and dpkg installs a new conffile over an existing unowned file: the copy
	# under test would vanish from apt's view (the first proof d run then took SparkyLinux's base-files 14.sparky9~0,
	# whose /bin is a directory, and the merged-/usr container lost /bin). dpkg never writes that one path here.
	printf 'path-exclude=/etc/apt/sources.list.d/sparky-stereo.sources\n' >/etc/dpkg/dpkg.cfg.d/lane-edition-source
	printf 'Types: deb\nURIs: https://deb.debian.org/debian\nSuites: testing\nComponents: contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n' \
		>/etc/apt/sources.list.d/debian-extra-components.sources
	apt_get update -q >$O/00-update-debian.log 2>&1 || fail "Debian archive update failed"
	apt_get -y -q install --no-install-recommends ca-certificates cpio zstd >$O/00-ca.log 2>&1 || fail "baseline bootstrap tools failed to install"
	# the answers the image carries (iso-build/rootfs.sh, SparkyLinux's own image): US keyboard, the firmware licences
	# accepted; without them firmware-ipw2x00's preinst exits 2 under DEBIAN_FRONTEND=noninteractive (r1103a, Opus 2026-11-04)
	printf '%s\n' "keyboard-configuration keyboard-configuration/layoutcode string us" \
		"firmware-ipw2x00 firmware-ipw2x00/license/accepted boolean true" \
		"firmware-ivtv firmware-ivtv/license/accepted boolean true" | debconf-set-selections
	# as the image build does (iso-build/rootfs.sh): sparky-grub-theme and sparky-info run grub-mkconfig when configured,
	# and in a container grub-probe cannot resolve the overlay root (r1103a case b: sparky-info's postinst exit 1), so
	# grub-mkconfig and os-prober are diverted stubs here, never the host's disks
	mkdir -p /boot/grub
	for f in /usr/bin/os-prober /usr/sbin/grub-mkconfig; do
		dpkg-divert --list "$f" | grep -q . || dpkg-divert --local --rename --add "$f" >/dev/null
		printf '#!/bin/sh\nexit 0\n' >"$f"; chmod 755 "$f"
	done
	cp /pin/* /etc/apt/preferences.d/
	# the names and Signed-By paths sparky-stereo-apt uses, so its own copies never conflict with these (apt refuses two
	# Signed-By values for one source)
	cp /keys/deb-multimedia-keyring.gpg /usr/share/keyrings/deb-multimedia-keyring.pgp
	printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /usr/share/keyrings/deb-multimedia-keyring.pgp\n' \
		>/etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources
	cp /keys/sparky-repo.asc /etc/apt/trusted.gpg.d/sparky-repo.asc
	printf 'Types: deb\nURIs: https://repo.sparkylinux.org/\nSuites: core tiamat\nComponents: main\nSigned-By: /etc/apt/trusted.gpg.d/sparky-repo.asc\n' \
		>/etc/apt/sources.list.d/sparky.sources
}
edition() {
    # The candidate is a copied, unsigned pool over the independently indexed published base.
    # Trusted applies only to this lane's hash-verified local pool, never a public archive.
    printf 'Types: deb\nURIs: file:/base\nSuites: mashtabba\nComponents: main\nSigned-By: /base/sparky-stereo-repo.asc\n' \
        >/etc/apt/sources.list.d/sparky-stereo.sources
    if [ "$1" = /cand ]; then
        printf '\nTypes: deb\nURIs: file:/pool\nSuites: ./\nTrusted: yes\n' \
            >>/etc/apt/sources.list.d/sparky-stereo.sources
    fi
}
update_all() {
    if [ -n "${E_FROZEN_PUBLIC_LISTS:-}" ]; then
        # The caller has authenticated and copied these public indexes. Updating
        # only the local edition must not change the solver's frozen public view.
        sha256sum --quiet -c "$E_FROZEN_PUBLIC_LISTS" || fail "frozen public indexes changed before upgrade"
        update_edition "$1" || fail "edition archive update failed: $1"
        sha256sum --quiet -c "$E_FROZEN_PUBLIC_LISTS" || fail "frozen public indexes changed during upgrade"
    else
        apt_get update -q >"$1" 2>&1 || fail "archive update failed: $1"
    fi
}
# refresh only the edition source: Debian, deb-multimedia and SparkyLinux keep the lists the install used
update_edition() {
	apt_get update -q -o Dir::Etc::SourceList=/etc/apt/sources.list.d/sparky-stereo.sources -o Dir::Etc::SourceParts=- \
		-o APT::Get::List-Cleanup=0 >"$1" 2>&1
}
summary() { grep -E '^(Inst|Remv|Conf|Purg)' "$1" | awk '{print $1}' | sort | uniq -c; }
snapshot() { dpkg-query -W -f='${db:Status-Abbrev} ${Package}:${Architecture} ${Version}\n' | sort >"$1"; }
# compare two snapshots: added, removed and changed packages (Package:Architecture), each to its own file PREFIX.{added,removed,changed}
compare() {
	local a=$1 b=$2 p=$3
	comm -13 <(awk '$1 == "ii" {print $2}' "$a" | sort) <(awk '$1 == "ii" {print $2}' "$b" | sort) >"$p.added"
	comm -23 <(awk '$1 == "ii" {print $2}' "$a" | sort) <(awk '$1 == "ii" {print $2}' "$b" | sort) >"$p.removed"
	join <(awk '$1 == "ii" {print $2, $3}' "$a" | sort) <(awk '$1 == "ii" {print $2, $3}' "$b" | sort) | awk '$2 != $3 {print $1}' >"$p.changed"
	echo "added $(wc -l <"$p.added"), removed $(wc -l <"$p.removed"), changed $(wc -l <"$p.changed")"
}
