#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The installer's transaction with generated stand-ins for CNJ's ZIP, in a disposable container as root, no network but loopback.
# Needs: sparky-pjeoffice installed (the .deb, or tests/dev-install), sparky-stereo-problems, openssl, python3, curl, ffmpeg.
# Usage: installer.sh FIXTURE_DIR   (a writable folder for the generated ZIPs and keys)
set -u
FX=${1:?a writable fixture folder}
TESTS=$(cd "$(dirname "$0")" && pwd)
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }
PJ=/usr/bin/sparky-pjeoffice
mkdir -p "$FX" && cd "$FX"
getent hosts pje-fixture.test >/dev/null || echo "127.0.0.1 pje-fixture.test" >> /etc/hosts
# a certificate authority for pje-fixture.test, trusted by the system store: curl and the certificate list both read it
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3 -subj /CN=pj18-fixture-ca >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj /CN=pje-fixture.test >/dev/null 2>&1
printf 'subjectAltName=DNS:pje-fixture.test\n' > san.ext
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 3 -extfile san.ext >/dev/null 2>&1
cp ca.crt /usr/local/share/ca-certificates/pj18-fixture-ca.crt && update-ca-certificates >/dev/null 2>&1
SYSTEM_COUNT=$(python3 -c "
import re,sys
print(len(re.findall(rb'-----BEGIN CERTIFICATE-----', open('/etc/ssl/certs/ca-certificates.crt','rb').read())))")
python3 "$TESTS/make-fixture.py" "$FX/www" 2.5.90u >/dev/null
python3 "$TESTS/make-fixture.py" "$FX/www" 2.5.91u >/dev/null
python3 "$TESTS/make-fixture.py" "$FX/www" 2.5.92u --bad-java >/dev/null
python3 "$TESTS/serve.py" "$FX/www" srv.crt srv.key 8443 > server.log 2>&1 & SERVER=$!
python3 "$TESTS/serve.py" "$FX/www" srv.crt srv.key 8444 --cut-at 3000 > server-cut.log 2>&1 & CUT=$!
trap 'kill $SERVER $CUT 2>/dev/null' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fs --max-time 2 -o /dev/null https://pje-fixture.test:8443/catalogue-none 2>/dev/null; [ $? = 22 ] && break; sleep 1; done
export LANG=en_US.UTF-8
problems() { sparky-stereo-problems list 2>/dev/null; }

echo "== 1. a file that is not the reviewed one is refused and deleted"
python3 - "$FX" <<'PY'
import json, sys
fx = sys.argv[1]
c = json.load(open(fx + '/www/catalogue-2.5.90u.json'))
v = c['versions']['2.5.90u']; v['sha256'] = '0' * 64
json.dump(c, open(fx + '/catalogue-wrong.json', 'w'))
PY
$PJ install --catalogue catalogue-wrong.json > out1.txt 2> err1.txt; RC=$?
t "install exits 1"                        "[ $RC = 1 ]"
t "nothing is installed"                   "[ ! -e /opt/pjeoffice-pro/current ] && [ ! -d /opt/pjeoffice-pro/versions/2.5.90u ]"
t "the refused file is deleted"            "[ ! -e /var/cache/sparky-pjeoffice/pjeoffice-pro-2.5.90u.zip ]"
t "the reason is said (SHA-256 differs)"   "grep -q 'SHA-256' err1.txt"
t "the problem is kept by the engine"      "problems | grep -q 'not the one that was reviewed'"
t "the reviewed file's own digest is not what the wrong catalogue says" "! python3 -c \"import hashlib,sys;sys.exit(0 if hashlib.sha256(open('$FX/www/pjeoffice-pro-v2.5.90u-linux_x64.zip','rb').read()).hexdigest()=='0'*64 else 1)\""

echo "== 2. an interrupted download keeps its part; the next run resumes it"
python3 - "$FX" <<'PY'
import json, sys
fx = sys.argv[1]
c = json.load(open(fx + '/www/catalogue-2.5.90u.json'))
v = c['versions']['2.5.90u']; v['url'] = v['url'].replace(':8443', ':8444')
json.dump(c, open(fx + '/catalogue-cut.json', 'w'))
PY
$PJ install --catalogue catalogue-cut.json > out2.txt 2> err2.txt; RC=$?
t "interrupted install exits 1"            "[ $RC = 1 ]"
t "the partial file is kept"               "[ -s /var/cache/sparky-pjeoffice/pjeoffice-pro-2.5.90u.zip.part ]"
t "nothing is installed"                   "[ ! -e /opt/pjeoffice-pro/current ]"
t "the problem is kept (the download)"     "problems | grep -q 'could not be fetched from CNJ'"
LANG=pt_BR.UTF-8 $PJ install --catalogue www/catalogue-2.5.90u.json > out3.txt 2> err3.txt; RC=$?
cp www/catalogue-2.5.90u.json catalogue-1.json
t "the next run succeeds"                  "[ $RC = 0 ]"
t "it says it resumes (in Portuguese)"     "grep -q 'Retomando um download anterior' out3.txt"
t "the version is in use"                  "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
t "the download problem is cleared"        "! problems | grep -q 'could not be fetched'"
t "the cache is empty again"               "[ -z \"\$(ls /var/cache/sparky-pjeoffice 2>/dev/null)\" ]"

echo "== 3. what the installed version is"
V=/opt/pjeoffice-pro/versions/2.5.90u
t "the program's updater is switched off"  "grep -q '^update.url=disabled' $V/pjeoffice-update.properties"
t "CNJ's original properties are kept"     "grep -q '^update.url=https://pje-office.pje.jus.br/pro/' $V/pjeoffice-update.properties.cnj"
t "the manifest of CNJ's files exists"     "grep -q ' pjeoffice-pro.jar\$' $V/SHA256SUMS.cnj"
t "java and ffmpeg.exe are executable"     "[ -x $V/jre/bin/java ] && [ -x $V/ffmpeg.exe ]"
t "the jar is not executable"              "[ ! -x $V/pjeoffice-pro.jar ]"
t "ffmpeg.exe of the managed folder links the system's" "[ \"\$(readlink /var/lib/sparky-pjeoffice/ffmpeg/ffmpeg.exe)\" = /usr/bin/ffmpeg ]"
python3 - "$V" <<'PY' > trust1.txt
import sys, zipfile
sys.path.insert(0, '/usr/lib/sparky-pjeoffice')
import jks
v = sys.argv[1]
orig = jks.read(zipfile.ZipFile(v + '/pjeoffice-pro.jar').read('pjeoffice.jks'), 'pjeoffice')
new = jks.read(open('/var/lib/sparky-pjeoffice/trust/2.5.90u/pjeoffice.jks', 'rb').read(), 'pjeoffice')
print('original', len(orig), 'new', len(new), 'preserved', new[:len(orig)] == orig)
PY
t "the list keeps every original entry, byte for byte" "grep -q 'preserved True' trust1.txt"
t "the list adds the system's certificates"            "[ \$(awk '{print \$4}' trust1.txt) -gt \$(awk '{print \$2}' trust1.txt) ]"
t "the state names the version and the digest"         "python3 -c \"import json;s=json.load(open('/var/lib/sparky-pjeoffice/state.json'));assert s['installed']=='2.5.90u' and len(s['zip_sha256'])==64\""

echo "== 4. an update keeps the previous version and switches only when every check passed"
$PJ install --catalogue www/catalogue-2.5.91u.json > out4.txt 2> err4.txt; RC=$?
t "update exits 0"                         "[ $RC = 0 ]"
t "the new version is in use"              "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.91u ]"
t "the previous version is kept"           "[ -d /opt/pjeoffice-pro/versions/2.5.90u ] && [ -f /var/lib/sparky-pjeoffice/trust/2.5.90u/pjeoffice.jks ]"
t "it says how to go back"                 "grep -q 'rollback' out4.txt"

echo "== 5. a version that fails its checks changes nothing and is told"
$PJ install --catalogue www/catalogue-2.5.92u.json > out5.txt 2> err5.txt; RC=$?
t "exits 10 (failed, the version in use is still in use)" "[ $RC = 10 ]"
t "the version in use is unchanged"        "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.91u ]"
t "no half-unpacked folder is left"        "[ -z \"\$(ls -d /opt/pjeoffice-pro/versions/.* 2>/dev/null | grep -v -e '/\.\$' -e '/\.\.\$')\" ] && [ ! -d /opt/pjeoffice-pro/versions/2.5.92u ]"
t "the problem names the version in use"   "problems | grep -q 'version 2.5.91u is still in use'"

echo "== 6. a failed switch restores the folder it replaced"
$PJ rollback > out6.txt 2>&1
t "rollback goes back one version"         "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
python3 - "$FX" <<'PY' > out7.txt 2>&1
import sys, os
sys.path.insert(0, '/usr/lib/sparky-pjeoffice')
import sparky_pjeoffice as m
real = os.replace
def refuse(src, dst):
    if str(src).endswith('.current.new'):
        raise OSError(28, 'No space left on device (injected for the test)')
    return real(src, dst)
os.replace = refuse
rc = m.install(sys.argv[1] + '/www/catalogue-2.5.91u.json')
print('rc', rc)
PY
t "the failed switch exits 10"             "grep -q '^rc 10' out7.txt"
t "the version in use is unchanged"        "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
t "the other version's folder is restored whole" "[ -f /opt/pjeoffice-pro/versions/2.5.91u/pjeoffice-pro.jar ] && [ ! -d /opt/pjeoffice-pro/versions/2.5.91u.old ]"
t "the reason is in the problem"           "problems | grep -q 'No space left on device'"
$PJ install --catalogue www/catalogue-2.5.91u.json > out8.txt 2>&1
t "the next run succeeds and clears it"    "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.91u ] && ! problems | grep -q 'No space left'"

echo "== 7. the certificate list follows the system's"
BEFORE=$(python3 -c "import json;print(json.load(open('/var/lib/sparky-pjeoffice/state.json'))['trust']['added'])")
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/extra.key -out /usr/local/share/ca-certificates/pj18-extra-root.crt -days 3 -subj /CN=pj18-extra-root >/dev/null 2>&1
update-ca-certificates >/dev/null 2>&1
$PJ trust --if-changed; RC=$?
AFTER=$(python3 -c "import json;print(json.load(open('/var/lib/sparky-pjeoffice/state.json'))['trust']['added'])")
t "trust --if-changed exits 0"             "[ $RC = 0 ]"
t "one certificate more"                   "[ $AFTER = $((BEFORE + 1)) ]"
M1=$(stat -c %Y /var/lib/sparky-pjeoffice/trust/2.5.91u/pjeoffice.jks); sleep 1
$PJ trust --if-changed
t "unchanged system list: the file is not rewritten" "[ $(stat -c %Y /var/lib/sparky-pjeoffice/trust/2.5.91u/pjeoffice.jks) = $M1 ]"
mv /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt.away
$PJ trust > out9.txt 2> err9.txt; RC=$?
mv /etc/ssl/certs/ca-certificates.crt.away /etc/ssl/certs/ca-certificates.crt
t "an unreadable system list is told, not skipped" "[ $RC = 1 ] && problems | grep -q 'could not be extended'"
$PJ trust; t "and cleared when it works again" "! problems | grep -q 'could not be extended'"

echo "== 8. nothing is asked of the network when it is not there"
STATE_BEFORE=$(sha256sum /var/lib/sparky-pjeoffice/state.json | cut -d' ' -f1)
$PJ check > out10.txt 2>&1; RC=$?
t "check says it could not read CNJ's address and exits 1" "[ $RC = 1 ] && grep -q 'could not be read' out10.txt"
t "check changed nothing"                  "[ \"\$(sha256sum /var/lib/sparky-pjeoffice/state.json | cut -d' ' -f1)\" = $STATE_BEFORE ] && [ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.91u ]"

echo "== 9. removal leaves the person's files"
mkdir -p "$HOME/.pjeoffice-pro" "$HOME/.config" && echo mine > "$HOME/.pjeoffice-pro/pjeoffice-pro.config" && echo mine > "$HOME/.config/sparkystereopjeofficerc"
$PJ remove > out11.txt 2>&1
t "the program is gone"                    "[ ! -e /opt/pjeoffice-pro ] && [ ! -e /var/lib/sparky-pjeoffice/state.json ] && [ ! -e /var/lib/sparky-pjeoffice/trust ]"
t "the person's files are untouched"      "[ \"\$(cat $HOME/.pjeoffice-pro/pjeoffice-pro.config)\" = mine ] && [ \"\$(cat $HOME/.config/sparkystereopjeofficerc)\" = mine ]"
t "no problem is left"                     "! problems | grep -q 'PJeOffice'"
echo
[ $FAIL = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $FAIL
