#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# The announcement of install-time downloads (ORDER 399b), in a clean Debian testing container, as root. What it proves, each check able to fail:
#   - the declaration reaches the Packages index and apt-cache show (flightgear-data-installer's own fields, from its package)
#   - a stand-in NetworkManager on the system bus (the real busctl asks it; only NetworkManager is not real) answers Metered: 1 yes, 3 guess-yes,
#     2 no, 4 guess-no, 0 unknown, and not at all
#   - on a terminal, `apt install` and `apt-get install` print the size and source before "Continue?", answering n installs and downloads nothing
#   - not metered: nothing extra; the same install is red without the package's hook
#   - -y: no question, the notice says so and the install goes on; an install of only the named package asks nothing either, and the notice says so
#   - an upgrade whose declaration did not change is not announced again; a changed one is
#   - a malformed declaration is said and the install goes on; the setting Announce works in its three values; nine languages
# Usage: docker run --rm --name flightgear-399b-test -v PKGS:/pkgs:ro -v THIS:/t:ro -v HELPERS:/h:ro IMAGE /t/test-install-downloads.sh
#   PKGS holds flightgear-data-installer_*.deb and sparky-stereo-apt_*.deb (the files of the second are used, not installed: it depends on SparkyLinux's repository)
export DEBIAN_FRONTEND=noninteractive
PASS=0; FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
has() { grep -q -- "$2" <<<"$1"; }
W=/tmp/idt; mkdir -p $W
sh /run/https-only-apt.sh >/dev/null 2>&1
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends dbus python3-dbus python3-gi python3-apt dpkg-dev systemd procps util-linux python3 xz-utils >/dev/null 2>&1 || { echo "FAIL cannot install the test tools"; exit 1; }

# the package's files (not the package: its dependencies are SparkyLinux's)
if ls /pkgs/sparky-stereo-apt_*.deb >/dev/null 2>&1; then
	dpkg-deb -x /pkgs/sparky-stereo-apt_*.deb $W/apt
	F=$W/apt
	echo "using the files of $(basename /pkgs/sparky-stereo-apt_*.deb)"
else
	F=
	echo "no package found in /pkgs"; exit 1
fi
install_hook() {
	install -D -m644 $F/etc/apt/apt.conf.d/61sparky-install-downloads /etc/apt/apt.conf.d/61sparky-install-downloads
	mkdir -p /usr/lib/sparky-stereo-apt /usr/share/sparky/sparky-stereo-apt
	cp -a $F/usr/lib/sparky-stereo-apt/. /usr/lib/sparky-stereo-apt/
	cp -a $F/usr/share/sparky/sparky-stereo-apt/. /usr/share/sparky/sparky-stereo-apt/
	ln -sf ../lib/sparky-stereo-apt/install-downloads /usr/bin/sparky-install-downloads
}
remove_hook() { rm -f /etc/apt/apt.conf.d/61sparky-install-downloads; }

# a stand-in NetworkManager
mkdir -p /run/dbus
cat >/etc/dbus-1/system.d/fake-nm.conf <<'EOT'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
 <policy user="root"><allow own="org.freedesktop.NetworkManager"/></policy>
 <policy context="default"><allow send_destination="org.freedesktop.NetworkManager"/></policy>
</busconfig>
EOT
dbus-daemon --system --fork --print-pid >$W/dbus.pid
sleep 1
nm_start() { python3 /t/fake-networkmanager.py >$W/nm.out 2>&1 & NMPID=$!; for _ in $(seq 1 40); do busctl --system status org.freedesktop.NetworkManager >/dev/null 2>&1 && return; sleep 0.25; done; }
nm_stop() { kill "$NMPID" 2>/dev/null; wait "$NMPID" 2>/dev/null; true; }
metered() { echo "$1" >/run/fake-nm-metered; }

# local repository: a plain package, and packages that declare a download (the real flightgear-data-installer, and small fixtures)
mkpkg() { # name version extra-control-lines
	local d=$W/pk/$1_$2; rm -rf $d; mkdir -p $d/DEBIAN
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: Test <t@example.org>\nDescription: test package %s\n%s\n' "$1" "$2" "$1" "$3" >$d/DEBIAN/control
	dpkg-deb -b $d /repo/ >/dev/null 2>&1
}
rm -rf /repo; mkdir -p /repo
mkpkg plain-pkg 1 ""
mkpkg data-pkg 1 "Depends: plain-pkg
Sparky-Install-Download-Size: 123456789
Sparky-Install-Download-Source: https://example.org/data-1.bin"
mkpkg solo-pkg 1 "Sparky-Install-Download-Size: 4096000
Sparky-Install-Download-Source: https://example.org/solo.bin"
mkpkg bad-pkg 1 "Sparky-Install-Download-Size: lots
Sparky-Install-Download-Source: https://example.org/x"
mkpkg half-pkg 1 "Sparky-Install-Download-Size: 5000"
cp /pkgs/flightgear-data-installer_*_all.deb /repo/
reindex() { (cd /repo && dpkg-scanpackages -m . >Packages 2>/dev/null && gzip -kf Packages); echo 'deb [trusted=yes] file:/repo ./' >/etc/apt/sources.list.d/test.list; apt-get update -qq >/dev/null 2>&1; }
reindex

echo "== the declaration in the index"
sh=$(apt-cache show flightgear-data-installer)
check "apt-cache show flightgear-data-installer carries Sparky-Install-Download-Size: 1883333376" has "$sh" "^Sparky-Install-Download-Size: 1883333376"
check "... and the source, an https address" has "$sh" "^Sparky-Install-Download-Source: https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.5-data.txz/download"
check "the Packages index line is there for apt's own tools (grep of the index)" grep -q "^Sparky-Install-Download-Size: 1883333376" /repo/Packages

nm_start
run_apt() { # answer cmd...
	local ans=$1; shift
	python3 /h/pty-answer.py "$ans" "$@" 2>&1
}
installed() { dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null; }

echo "== red: without the hook, a metered install shows nothing"
remove_hook
metered 1
out=$(run_apt n apt-get install data-pkg)
echo "$out" | sed -n '/NEW packages/,$p' | head -n 12
check "red: no warning, no size, no source" bash -c "! grep -q -e 'metered' -e '117' -e 'example.org/data-1' <<<'$(echo "$out" | tr "'" ' ')'"
check "red: and the install asks only apt's own question" has "$out" "Do you want to continue"

echo "== green: with the hook (apt-get, a terminal, metered: yes)"
install_hook
metered 1
out=$(run_apt n apt-get install data-pkg)
echo "$out" | sed -n '/NEW packages/,$p' | head -n 14
check "the notice says the connection is metered and what NetworkManager said" has "$out" "metered (NetworkManager says: yes)"
check "the notice names the package, its size (117.7 MiB) and its source" has "$out" "data-pkg: 117.7 MiB from https://example.org/data-1.bin"
check "the notice comes before apt's question" bash -c "n1=\$(grep -n 'data-pkg: 117.7' <<<'$out' | head -1 | cut -d: -f1); n2=\$(grep -n 'Do you want to continue' <<<'$out' | head -1 | cut -d: -f1); [ -n \"\$n1\" ] && [ -n \"\$n2\" ] && [ \$n1 -lt \$n2 ]"
check "it says answering n downloads nothing" has "$out" "Answer n to the question below and nothing is downloaded"
check "answering n: nothing is installed" test "$(installed data-pkg)" != installed
check "answering n: nothing was downloaded into apt's archive" bash -c "! ls /var/cache/apt/archives/data-pkg* 2>/dev/null | grep -q ."

echo "== the same for the apt command"
out=$(run_apt n apt install data-pkg)
check "apt install: the notice is there too, with size and source" bash -c "grep -q 'data-pkg: 117.7 MiB from https://example.org/data-1.bin' <<<'$out' && grep -q 'metered' <<<'$out'"
check "apt install: answering n installs nothing" test "$(installed data-pkg)" != installed

echo "== NetworkManager's other answers"
for v in 3:guess-yes; do
	metered "${v%%:*}"; out=$(run_apt n apt-get install data-pkg)
	check "Metered=${v%%:*} (${v#*:}): shown" has "$out" "NetworkManager says: ${v#*:}"
done
for v in 2:no 4:guess-no; do
	metered "${v%%:*}"; out=$(run_apt n apt-get install data-pkg)
	check "Metered=${v%%:*} (${v#*:}): nothing extra is shown" bash -c "! grep -q -e 'metered' -e 'data-pkg: 117' -e 'example.org/data-1' <<<'$out'"
done
metered 0; out=$(run_apt n apt-get install data-pkg)
check "Metered=0 (unknown): shown, and it says it could not tell" bash -c "grep -q 'Could not tell whether this connection is metered' <<<'$out' && grep -q 'data-pkg: 117.7 MiB' <<<'$out'"
nm_stop
out=$(run_apt n apt-get install data-pkg)
echo "$out" | grep -i "could not tell" | head -n 2
check "NetworkManager not on the bus: shown, and it says what it read" bash -c "grep -q 'Could not tell whether this connection is metered (NetworkManager did not answer' <<<'$out' && grep -q 'data-pkg: 117.7 MiB' <<<'$out'"
nm_start; metered 2

echo "== not metered: the install runs, and a package that declares nothing never shows anything"
out=$(run_apt y apt-get install data-pkg)
check "not metered, answering y: installed, no notice" bash -c "test \$(dpkg-query -W -f='\${db:Status-Status}' data-pkg) = installed && ! grep -q 'data-pkg: 117' <<<'$out'"
metered 1
out=$(run_apt n apt-get install plain-pkg)
check "metered, a package without a declaration: nothing extra" bash -c "! grep -q -e 'metered' -e 'download more' <<<'$out'"
apt-get -y -qq purge data-pkg plain-pkg >/dev/null 2>&1

echo "== -y: no question; the notice says so; and an install of only the named package: apt asks nothing, the notice says so"
out=$(apt-get -y install data-pkg 2>&1)
echo "$out" | grep -A3 -i "metered" | head -n 6
check "-y, metered: the notice is printed and says no question is asked here" bash -c "grep -q 'data-pkg: 117.7 MiB' <<<'$out' && grep -q 'No question is asked here' <<<'$out'"
check "-y: the install went on" test "$(installed data-pkg)" = installed
apt-get -y -qq remove data-pkg plain-pkg >/dev/null 2>&1
out=$(run_apt n apt-get install solo-pkg)
check "only the named package (apt asks nothing): the notice says so and to press Ctrl+C" bash -c "grep -q 'solo-pkg: 3.9 MiB from https://example.org/solo.bin' <<<'$out' && grep -q 'apt asks no question here' <<<'$out' && grep -q 'Ctrl+C' <<<'$out'"
apt-get -y -qq remove solo-pkg >/dev/null 2>&1

echo "== the setting"
printf 'Sparky::Install-Downloads::Announce "never";\n' >/etc/apt/apt.conf.d/99test
metered 1; out=$(run_apt n apt-get install data-pkg)
check "never: nothing is shown on a metered connection" bash -c "! grep -q -e 'metered' -e 'data-pkg: 117' <<<'$out'"
printf 'Sparky::Install-Downloads::Announce "always";\n' >/etc/apt/apt.conf.d/99test
metered 2; out=$(run_apt n apt-get install data-pkg)
check "always: shown on a connection that is not metered, without the metered sentence" bash -c "grep -q 'data-pkg: 117.7 MiB' <<<'$out' && ! grep -q 'This connection is metered' <<<'$out'"
printf 'Sparky::Install-Downloads::Announce "sometimes";\n' >/etc/apt/apt.conf.d/99test
metered 1; out=$(run_apt n apt-get install data-pkg)
check "an invalid value is said and metered is used" bash -c "grep -q 'Sparky::Install-Downloads::Announce is \"sometimes\"' <<<'$out' && grep -q 'data-pkg: 117.7 MiB' <<<'$out'"
rm -f /etc/apt/apt.conf.d/99test

echo "== malformed declarations are said and never stop the install"
metered 1
out=$(run_apt y apt-get install bad-pkg)
check "bad size: said, install went on" bash -c "grep -q 'bad-pkg is ignored' <<<'$out' && test \$(dpkg-query -W -f='\${db:Status-Status}' bad-pkg) = installed"
out=$(run_apt y apt-get install half-pkg)
check "size without source: said, install went on" bash -c "grep -q 'half-pkg is ignored' <<<'$out' && test \$(dpkg-query -W -f='\${db:Status-Status}' half-pkg) = installed"
apt-get -y -qq remove bad-pkg half-pkg >/dev/null 2>&1

echo "== upgrades: announced only when the download changes"
apt-get -y -qq install data-pkg >/dev/null 2>&1
mkpkg data-pkg 2 "Depends: plain-pkg
Sparky-Install-Download-Size: 123456789
Sparky-Install-Download-Source: https://example.org/data-1.bin"
reindex; metered 1
out=$(run_apt n apt-get install data-pkg)
check "an upgrade with the same declaration: not announced (the data stays)" bash -c "! grep -q 'data-pkg: 117' <<<'$out'"
mkpkg data-pkg 3 "Depends: plain-pkg
Sparky-Install-Download-Size: 234567890
Sparky-Install-Download-Source: https://example.org/data-3.bin"
reindex
out=$(run_apt n apt-get install data-pkg)
check "an upgrade with another size and source: announced with the new ones" has "$out" "data-pkg: 223.7 MiB from https://example.org/data-3.bin"
apt-get -y -qq purge data-pkg plain-pkg >/dev/null 2>&1

echo "== the reader's own command (what Stereo APTus uses) and the languages"
metered 1
j=$(/usr/lib/sparky-stereo-apt/install-downloads check --json flightgear-data-installer)
check "check --json: the downloader's 1.75 GiB and its source, announce true" python3 -c "
import json,sys
d=json.loads(sys.argv[1]); x=d['downloads'][0]
assert d['announce'] and d['state']=='yes' and x['package']=='flightgear-data-installer' and x['size']==1883333376 and x['size_text']=='1.75 GiB' and x['source'].startswith('https://sourceforge.net/')
" "$j"
metered 2
j=$(/usr/lib/sparky-stereo-apt/install-downloads check --json flightgear-data-installer)
check "check --json, not metered: announce false" python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['announce'] is False and d['downloads']==[]" "$j"
metered 1
for pair in de_DE.UTF-8:"getaktet" fr_FR.UTF-8:"limitée" pl_PL.UTF-8:"taryfowane" pt_BR.UTF-8:"limitada" ja_JP.UTF-8:"従量制" ko_KR.UTF-8:"종량제" zh_CN.UTF-8:"按流量计费" zh_TW.UTF-8:"按流量計費" en_US.UTF-8:"is metered"; do
	loc=${pair%%:*}; want=${pair#*:}
	apt-get -y -qq purge data-pkg plain-pkg >/dev/null 2>&1
	out=$(LC_ALL=$loc python3 /h/pty-answer.py n apt-get install data-pkg 2>&1)
	check "language $loc" has "$out" "$want"
done
python3 - <<'PY' && ok "the nine language files have the same keys and placeholders" || bad "language files differ"
import json, glob, string, os
d='/usr/share/sparky/sparky-stereo-apt/install-downloads'
en=json.load(open(d+'/en.json'))
files=sorted(glob.glob(d+'/*.json'))
assert len(files)==9, files
for f in files:
    t=json.load(open(f))
    assert set(t)==set(en), f
    for k in en:
        assert {x for _,x,_,_ in string.Formatter().parse(en[k]) if x}=={x for _,x,_,_ in string.Formatter().parse(t[k]) if x}, (f,k)
PY
nm_stop; kill "$(cat $W/dbus.pid)" 2>/dev/null
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
