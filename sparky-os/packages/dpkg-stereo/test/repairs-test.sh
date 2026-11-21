#!/bin/sh
# dpkg-stereo 0.1.44 (rows 629 and 802): what the published edition left behind is repaired, and nothing is
# downloaded behind the person's back on a metered connection.
#   1. a person who is not root gets one sentence (LOCAL23, exit 2), no traceback;
#   2. the records 0.1.41 and 0.1.42 lost (a projected conffile the same in two versions) come back, from APT's cache
#      or a configured source, the source's download held while the connection is metered and made once it is not;
#      the package's next change asks nothing;
#   3. a conffile another package's diversion kept from being installed (the published edition: nano's /etc/nanorc,
#      initramfs-tools' update-initramfs.conf) is installed by reinstalling its package after the dpkg run: held when
#      metered, done from APT's cache, a person's edit of the diverting package's file untouched.
# Usage (root, in a throwaway container of the published edition, which has dpkg-stereo 0.1.41, nano and
# initramfs-tools with their conffiles lost): repairs-test.sh DPKG-STEREO.deb WORKDIR DEBS
#   DEBS holds the installed nano and initramfs-tools .deb files (the cache case). MODE=archive instead downloads them
#   (network, not metered) and runs only part 3.
# NetworkManager's Metered property is read through busctl; a stand-in busctl first on PATH answers it.
set -u
DEB=$1 W=$2 DEBS=${3:-}
mkdir -p "$W/bin" "$W/repo"
pass=0 fail=0
ok() { echo "PASS $*"; pass=$((pass + 1)); }
no() { echo "FAIL $*"; fail=$((fail + 1)); }
check() { if eval "$1"; then ok "$2"; else no "$2"; fi; }
meter() { printf '#!/bin/sh\necho "u %s"\n' "$1" >"$W/bin/busctl"; chmod 755 "$W/bin/busctl"; }
export PATH="$W/bin:$PATH" DEBIAN_FRONTEND=noninteractive
meter 2
hash_of() { dpkg-query -W -f='${Conffiles}\n' "$1" | awk -v p="$2" '$1 == p {print $2}'; }
lost() { [ "$(hash_of "$1" "$2")" = newconffile ] && [ ! -e "$3" ]; }

mk() {	# mk NAME VERSION VALUE: a conffile in /etc/default (shell) and one in /etc/systemd (ini), as on the A10
	d=$W/$1-$2
	mkdir -p "$d/DEBIAN" "$d/etc/default" "$d/etc/systemd"
	printf '# %s defaults, the same in every version.\n# A second comment line the program never reads.\nSETTING=%s\n' "$1" "$3" >"$d/etc/default/$1"
	printf '#  This file is part of %s.\n#\n# A comment the program never reads.\n[Main]\n#Commented=yes\nValue=%s\n' "$1" "$3" >"$d/etc/systemd/$1.conf"
	printf '/etc/default/%s\n/etc/systemd/%s.conf\n' "$1" "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: conffile kept across versions\n' "$1" "$2" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_all.deb" >/dev/null
}
recorded() { cat "/var/lib/dpkg-stereo/records/$1.tsv" 2>/dev/null | grep -c "^$2$(printf '\t')"; }

if [ "${MODE:-}" != archive ]; then
	# 2. the lost records, made by the published 0.1.41 before the new version is installed
	mk uc-cache 1.0 10; mk uc-cache 2.0 10; mk uc-cache 3.0 30
	mk uc-source 1.0 10; mk uc-source 2.0 10
	for v in 1.0 2.0; do dpkg -i "$W/uc-cache_${v}_all.deb" "$W/uc-source_${v}_all.deb" </dev/null >"$W/uc-$v.log" 2>&1; done
	check '[ "$(recorded uc-cache /etc/default/uc-cache)" = 0 ] && [ "$(recorded uc-source /etc/systemd/uc-source.conf)" = 0 ]' \
		"red precondition: the verifier before 0.1.44 left the four projected conffiles without a record"
	cp "$W/uc-cache_2.0_all.deb" /var/cache/apt/archives/uc-cache_2.0_all.deb
	cp "$W/uc-source_2.0_all.deb" "$W/repo/"
	f=uc-source_2.0_all.deb
	{ dpkg-deb -f "$W/repo/$f"; printf 'Filename: ./%s\nSize: %s\nSHA256: %s\n' "$f" "$(stat -c %s "$W/repo/$f")" \
		"$(sha256sum "$W/repo/$f" | cut -d' ' -f1)"; } >"$W/repo/Packages"
	printf 'Types: deb\nURIs: file:%s/repo\nSuites: ./\nTrusted: yes\n' "$W" >/etc/apt/sources.list.d/uc.sources
	apt-get -q -o Dir::Etc::SourceList=/etc/apt/sources.list.d/uc.sources -o Dir::Etc::SourceParts=- \
		-o APT::Get::List-Cleanup=0 update >/dev/null 2>&1
	meter 1
	dpkg -i "$DEB" </dev/null >"$W/install.log" 2>&1
	echo "  installed $(dpkg-query -W -f='${Version}' dpkg-stereo)"
	# 1. not root, asked of the version just installed
	out=$(runuser -u nobody -- dpkg-stereo --verify --deep 2>&1); rc=$?
	echo "$out" | sed 's/^/  nobody: /'
	check '[ "$rc" = 2 ] && echo "$out" | grep -q "This needs root: sudo dpkg-stereo --verify --deep" && ! echo "$out" | grep -q Traceback' \
		"not root: one sentence with the person's own command, exit 2, no traceback (rc=$rc)"

	check '[ "$(recorded uc-cache /etc/default/uc-cache)" = 1 ] && [ "$(recorded uc-cache /etc/systemd/uc-cache.conf)" = 1 ]' \
		"lost records from APT's cache: both conffiles of uc-cache recorded again"
	dpkg-stereo --problems >"$W/problems.log" 2>&1
	grep -i -E 'uc-source|metered' "$W/install.log" "$W/problems.log" | sed 's/^/  said: /' | cut -c1-240 | head -6
	check '[ "$(recorded uc-source /etc/default/uc-source)" = 0 ] && grep -q "connection is metered" "$W/install.log" "$W/problems.log"' \
		"metered: uc-source's download from its source is held and said"
	check '! dpkg-stereo --problems 2>&1 | grep -q "next upgrade of uc-source"' "no remedy promises the next upgrade for a conffile"
	meter 2
	dpkg -i "$W/uc-cache_2.0_all.deb" </dev/null >"$W/again.log" 2>&1     # any dpkg run, APT's state unchanged
	check '[ "$(recorded uc-source /etc/default/uc-source)" = 1 ] && [ "$(recorded uc-source /etc/systemd/uc-source.conf)" = 1 ]' \
		"not metered any more: the next dpkg run fetches uc-source's original and records both conffiles"
	dpkg -i "$W/uc-cache_3.0_all.deb" </dev/null >"$W/3.log" 2>&1; rc=$?
	check '[ "$rc" = 0 ] && ! grep -q "Configuration file" "$W/3.log" && [ ! -e /etc/default/uc-cache.dpkg-new ] && grep -q SETTING=30 /etc/default/uc-cache' \
		"uc-cache 3.0 changes the conffiles: no question, installed (rc=$rc)"
	dpkg -P uc-cache uc-source >/dev/null 2>&1
	rm -f /etc/apt/sources.list.d/uc.sources
fi

# 3. the conffiles a diversion kept from their package
check 'lost nano /etc/nanorc /etc/nanorc.debian && lost initramfs-tools /etc/initramfs-tools/update-initramfs.conf /etc/initramfs-tools/update-initramfs.conf.debian' \
	"red precondition: nano's and initramfs-tools' conffiles are newconffile with nothing at the diverted name"
echo '# the person: an edit of the console nanorc' >>/etc/nanorc
[ "$(dpkg-query -W -f='${Version}' dpkg-stereo)" = "$(dpkg-deb -f "$DEB" Version)" ] || dpkg -i "$DEB" </dev/null >"$W/install.log" 2>&1
check '[ -s /var/lib/dpkg-stereo/diverted-conffiles.pending ]' "the hook found them and left them pending for the unit"
if [ "${MODE:-}" = archive ]; then
	meter 2
	dpkg-stereo --repair-diverted >"$W/archive.log" 2>&1; rc=$?
	sed 's/^/  repair: /' "$W/archive.log"
	check '[ "$rc" = 0 ] && grep -q "is now at /etc/nanorc.debian" "$W/archive.log"' "not metered, no cache: downloaded and installed (rc=$rc)"
else
	meter 1
	dpkg-stereo --repair-diverted >"$W/metered.log" 2>&1; rc=$?
	check '[ "$rc" = 1 ] && grep -q "metered" "$W/metered.log" && lost nano /etc/nanorc /etc/nanorc.debian' \
		"metered, no cache: held and said, nothing downloaded (rc=$rc)"
	grep -E 'never installed' "$W/metered.log" | head -2 | sed 's/^/  held: /'
	cp "$DEBS"/nano_*.deb "$DEBS"/initramfs-tools_*.deb /var/cache/apt/archives/
	dpkg-stereo --repair-diverted >"$W/cache.log" 2>&1; rc=$?
	sed 's/^/  repair: /' "$W/cache.log" | fold -w 230
	check '[ "$rc" = 0 ] && grep -q "is now at /etc/nanorc.debian" "$W/cache.log" && grep -q "update-initramfs.conf.debian" "$W/cache.log"' \
		"metered, both .deb files in APT's cache: installed with no download, and said (rc=$rc)"
fi
check '! lost nano /etc/nanorc /etc/nanorc.debian && [ -s /etc/nanorc.debian ] && ! lost initramfs-tools /etc/initramfs-tools/update-initramfs.conf /etc/initramfs-tools/update-initramfs.conf.debian' \
	"both conffiles at their diverted names, dpkg's hash recorded (nano $(hash_of nano /etc/nanorc))"
check 'grep -q "the person: an edit of the console nanorc" /etc/nanorc && [ -L /etc/initramfs-tools/update-initramfs.conf ]' \
	"the diverting packages' files at the paths are untouched, the person's edit kept"
check '[ ! -e /var/lib/dpkg-stereo/diverted-conffiles.pending ] && ! dpkg-stereo --problems 2>&1 | grep -q "never installed"' \
	"nothing left pending, the problem cleared"
dpkg-stereo --verify >"$W/verify.log" 2>&1
sed 's/^/  verify: /' "$W/verify.log" | head -4
check '[ "$(grep -c -E "^(CHANGED|MISSING|LCCHANGED)" "$W/verify.log")" = 0 ] && dpkg --verify sparky-stereo-console 2>&1 | grep -q " /etc/nanorc$"' \
	"--verify clean; the edit of the console's own nanorc (no conffile, not projected) is dpkg's to name: dpkg --verify names it"
echo "$pass PASS, $fail FAIL"
[ "$fail" = 0 ] && echo "ALL PASS"
