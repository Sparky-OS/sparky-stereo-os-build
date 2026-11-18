#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As root in a container made from the flat-repository image (no network): the package's life with generated stand-ins for CNJ's ZIP: installed by apt, updated to a second
# generated version (unpack, then the new reviewed catalogue, then setup: what an update's dpkg does), removed, purged. Usage: lifecycle.sh OUT   Needs /debs /pkg /fx /real
set -u
OUT=${1:?}; mkdir -p "$OUT"; FX=/fx; cd $FX
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }
getent hosts pje-fixture.test >/dev/null || echo "127.0.0.1 pje-fixture.test" >> /etc/hosts
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3 -subj /CN=pj18-fixture-ca >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj /CN=pje-fixture.test >/dev/null 2>&1
printf 'subjectAltName=DNS:pje-fixture.test\n' > san.ext
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 3 -extfile san.ext >/dev/null 2>&1
cp ca.crt /usr/local/share/ca-certificates/pj18-fixture-ca.crt && update-ca-certificates >/dev/null 2>&1
python3 /pkg/tests/make-fixture.py $FX/www 2.5.90u >/dev/null; python3 /pkg/tests/make-fixture.py $FX/www 2.5.91u >/dev/null
python3 /pkg/tests/serve.py $FX/www srv.crt srv.key 8443 > server.log 2>&1 & S1=$!
sleep 2
mkdir -p /usr/share/sparky-pjeoffice; echo 'path-exclude=/usr/share/sparky-pjeoffice/catalogue.json' > /etc/dpkg/dpkg.cfg.d/pj18-fixture-catalogue
cp $FX/www/catalogue-2.5.90u.json /usr/share/sparky-pjeoffice/catalogue.json
echo "== install by apt"
apt-get -y install sparky-pjeoffice > "$OUT/install.txt" 2>&1
t "installed and in use: 2.5.90u" "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
t "the package, the codec package and the files of the integration are there" "dpkg -s sparky-pjeoffice sparky-pjeoffice-codec 2>/dev/null | grep -c 'Status: install ok installed' | grep -q 2 && [ -x /usr/bin/sparky-pjeoffice-tray ] && [ -f /etc/xdg/autostart/sparky-pjeoffice-tray.desktop ] && [ -f /usr/share/kio/servicemenus/sparky-pjeoffice-sign.desktop ] && [ -f /usr/share/applications/sparky-pjeoffice.desktop ]"
# the person's own files, made before the removal
mkdir -p /root/.pjeoffice-pro /root/.config /root/.local/state/sparky-pjeoffice
echo mine > /root/.pjeoffice-pro/pjeoffice-pro.config; echo mine > /root/.config/sparkystereopjeofficerc; echo log > /root/.local/state/sparky-pjeoffice/signer.log
echo "== update to a second generated version"
dpkg --unpack /debs/sparky-pjeoffice_0.1.0+lc1_amd64.deb > "$OUT/update.txt" 2>&1
cp $FX/www/catalogue-2.5.91u.json /usr/share/sparky-pjeoffice/catalogue.json
dpkg --configure sparky-pjeoffice >> "$OUT/update.txt" 2>&1; RC=$?
t "the setup succeeds" "[ $RC = 0 ]"
t "2.5.91u is in use, 2.5.90u is kept" "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.91u ] && [ -d /opt/pjeoffice-pro/versions/2.5.90u ]"
t "the state names both" "python3 -c \"import json;s=json.load(open('/var/lib/sparky-pjeoffice/state.json'));assert s['installed']=='2.5.91u' and s['previous']=='2.5.90u'\""
t "the person's files are untouched by the update" "[ \"\$(cat /root/.pjeoffice-pro/pjeoffice-pro.config)\" = mine ]"
echo "== removal"
apt-get -y remove sparky-pjeoffice > "$OUT/remove.txt" 2>&1
t "the program, its list and the state are gone" "[ ! -e /opt/pjeoffice-pro ] && [ ! -e /var/lib/sparky-pjeoffice/state.json ] && [ ! -e /var/lib/sparky-pjeoffice/trust ]"
t "the package's own files are gone" "[ ! -e /usr/bin/sparky-pjeoffice ] && [ ! -e /usr/share/kio/servicemenus/sparky-pjeoffice-sign.desktop ]"
t "the person's certificates, settings and files are there" "[ \"\$(cat /root/.pjeoffice-pro/pjeoffice-pro.config)\" = mine ] && [ \"\$(cat /root/.config/sparkystereopjeofficerc)\" = mine ] && [ -f /root/.local/state/sparky-pjeoffice/signer.log ]"
t "the autostart file (a conffile) stays until the purge" "[ -f /etc/xdg/autostart/sparky-pjeoffice-tray.desktop ]"
t "no problem of the package is left in the engine" "! sparky-stereo-problems list 2>/dev/null | grep -q sparky-pjeoffice"
echo "== purge"
apt-get -y purge sparky-pjeoffice > "$OUT/purge.txt" 2>&1
t "the autostart file and the state folders are gone" "[ ! -e /etc/xdg/autostart/sparky-pjeoffice-tray.desktop ] && [ ! -e /var/lib/sparky-pjeoffice ] && [ ! -e /var/cache/sparky-pjeoffice ]"
t "the person's files are still there after the purge" "[ \"\$(cat /root/.pjeoffice-pro/pjeoffice-pro.config)\" = mine ] && [ \"\$(cat /root/.config/sparkystereopjeofficerc)\" = mine ]"
kill $S1 2>/dev/null
echo; [ $FAIL = 0 ] && echo "RESULT: PASS (lifecycle)" || echo "RESULT: FAIL (lifecycle)"
exit $FAIL
