#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Install, use and purge of the .deb in a throwaway debian:testing container (needs root).
# Last update 2026/10/02
DEB=${1:?usage: pkg-test.sh package.deb}
FAILS=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
C=/etc/chrony/chrony.conf
cp $C /tmp/chrony.conf.orig
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
dpkg -i "$DEB" >/dev/null 2>&1; apt-get -y -f install >/dev/null 2>&1
ok "sources file written for BR" "grep -q 'server a.st1.ntp.br iburst nts' /etc/chrony/sources.d/sparky-stereo.sources"
ok "chrony.conf untouched by install" "cmp -s $C /tmp/chrony.conf.orig"
ok "BR: authselectmode prefer snippet" "grep -qx 'authselectmode prefer' /etc/chrony/conf.d/sparky-stereo-auth.conf"
ok "nocerttimecheck conffile" "grep -qx 'nocerttimecheck 1' /etc/chrony/conf.d/sparky-stereo.conf"
ok "conffile is registered" "dpkg-query -W -f='\${Conffiles}' sparky-stereo-time | grep -q sparky-stereo.conf"
ok "depends on ca-certificates" "dpkg-query -W -f='\${Depends}' sparky-stereo-time | grep -q ca-certificates"
dpkg -r sparky-stereo-time >/dev/null 2>&1
ok "remove leaves chrony.conf identical" "cmp -s $C /tmp/chrony.conf.orig"
ok "remove deletes the sources file" "[ ! -e /etc/chrony/sources.d/sparky-stereo.sources ]"
ok "remove deletes the generated snippet" "[ ! -e /etc/chrony/conf.d/sparky-stereo-auth.conf ]"
dpkg -i "$DEB" >/dev/null 2>&1
dpkg -P sparky-stereo-time >/dev/null 2>&1
ok "purge leaves chrony.conf identical" "cmp -s $C /tmp/chrony.conf.orig"
ok "purge removes the conffile" "[ ! -e /etc/chrony/conf.d/sparky-stereo.conf ]"
ok "purge removes the tool and the data" "[ ! -e /usr/bin/sparky-stereo-time ] && [ ! -e /usr/share/sparky-stereo-time ]"
echo "failures: $FAILS"
exit $((FAILS > 0))
