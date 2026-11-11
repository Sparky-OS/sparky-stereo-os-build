#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-3b: "sparky-stereo-integration is installed" always means "the catalogue (integrations.map) is present". In a clean container
# with the dependencies of the runner already installed (no network), a flat local repository of the given .deb files: apt-get install
# sparky-stereo-integration alone, then the runner's Install action (a fake konsole records what apt would be asked to install), then
# remove and purge in both orders. Run as root.
# Usage: catalogue-proof.sh REPODIR      exit 0 only when every case matches
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
REPO=${1:?a folder of .deb files}
fails=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* /etc/apt/apt.conf.d/00sparky-block-plain-http
mkdir -p /srv/repo /var/lib/apt/lists/partial; rm -rf /srv/repo/*; cp "$REPO"/*.deb /srv/repo/
(cd /srv/repo && dpkg-scanpackages -m . 2>/dev/null >Packages)
echo "deb [trusted=yes] file:/srv/repo ./" >/etc/apt/sources.list
apt-get -qq update 2>&1 | grep -E '^E:'
MAP=/usr/share/sparky-stereo/integrations.map
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/konsole" <<EOS
#!/bin/sh
shift 5
echo "\$*" >>"$T/installs"
EOS
chmod +x "$T/bin/konsole"
audit() { apt-get check >/dev/null 2>&1 && [ -z "$(dpkg --audit 2>&1)" ]; }
fresh() { apt-get -y -qq purge sparky-stereo-integration sparky-stereo-integrations sparky-stereo-integration-catalogue sparky-stereo-align sparky-stereo-mkv-mark >/dev/null 2>&1; rm -f "$T/installs"; }

echo "== apt-get install sparky-stereo-integration, alone"
fresh
apt-get -y -qq install sparky-stereo-integration >"$T/apt.log" 2>&1; rc=$?
[ "$rc" = 0 ]; ok $? "install: exit $rc"
[ -f "$MAP" ] && [ -s "$MAP" ]; ok $? "the catalogue is there after the runner alone is installed ($([ -f "$MAP" ] && echo "owner $(dpkg -S "$MAP" | cut -d: -f1)" || echo absent))"
dpkg -S "$MAP" >/dev/null 2>&1; ok $? "the catalogue belongs to an installed package"
echo "== the Install action"
HOME=$T/home XDG_STATE_HOME=$T/home/state SPARKY_STEREO_INTEGRATION_UI=none PATH=$T/bin:$PATH sparky-stereo-integration install hugin-tools >"$T/out" 2>"$T/err"; rc=$?
[ "$rc" = 0 ]; ok $? "Install hugin-tools: exit $rc ($(head -c 160 "$T/err" | tr '\n' ' '))"
[ "$(cat "$T/installs" 2>/dev/null)" = "hugin-tools sparky-stereo-align" ]; ok $? "it asks apt for the program and its pack: '$(cat "$T/installs" 2>/dev/null)'"
echo "== remove and purge, both orders"
for order in "integration catalogue" "catalogue integration"; do
	fresh; apt-get -y -qq install sparky-stereo-integration >/dev/null 2>&1
	for p in $order; do
		case $p in integration) n=sparky-stereo-integration ;; *) n=sparky-stereo-integration-catalogue ;; esac
		apt-get -y -qq remove "$n" >/dev/null 2>&1; rc=$?
		[ "$rc" = 0 ] && audit; ok $? "$order: remove $n: exit $rc, apt-get check and dpkg --audit clean"
	done
	for p in $order; do
		case $p in integration) n=sparky-stereo-integration ;; *) n=sparky-stereo-integration-catalogue ;; esac
		apt-get -y -qq purge "$n" >/dev/null 2>&1; rc=$?
		[ "$rc" = 0 ] && audit; ok $? "$order: purge $n: exit $rc, clean"
	done
	[ -z "$(dpkg-query -W -f '${db:Status-Abbrev}${Package}\n' 'sparky-stereo-integration*' 2>/dev/null | grep -v '^un')" ]; ok $? "$order: nothing of the pair is left (dpkg state empty)"
done
echo "== runner and meta together"
fresh
if [ -f /srv/repo/sparky-stereo-integrations_*.deb ] || ls /srv/repo/sparky-stereo-integrations_*.deb >/dev/null 2>&1; then
	apt-get -y -qq install sparky-stereo-integrations >/dev/null 2>&1; rc=$?
	[ "$rc" = 0 ] && [ -f "$MAP" ] && audit; ok $? "the meta installs: exit $rc, catalogue present, clean"
	apt-get -y -qq remove sparky-stereo-integrations >/dev/null 2>&1
	[ -f "$MAP" ] && dpkg-query -W -f '${db:Status-Abbrev}\n' sparky-stereo-integration | grep -q '^ii'; ok $? "removing the meta leaves the runner and its catalogue"
fi
echo "failures: $fails"
[ "$fails" = 0 ]
