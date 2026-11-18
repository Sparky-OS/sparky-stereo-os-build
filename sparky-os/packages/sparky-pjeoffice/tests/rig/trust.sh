#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As root in a container with sparky-pjeoffice installed from its .deb and CNJ's program fetched by it, no network but loopback: a generated authority is added to the SYSTEM's
# certificates (update-ca-certificates), `sparky-pjeoffice trust` merges it into the program's own list, and the program's own HTTPS codec (PjeWebGlobal.HTTPS_CODEC,
# through /classes/AppTrustProbe) reads a page of a generated server: refused with the program's original list on the class path (red), accepted with the merged list first (green).
# Usage: trust.sh OUT   Needs /classes, /pkg (tests/serve.py)
set -u
OUT=${1:?}; mkdir -p "$OUT"; cd "$OUT"
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }
APP=/opt/pjeoffice-pro/current; JAVA=$APP/jre/bin/java; TRUST=/var/lib/sparky-pjeoffice/trust/$(basename "$(readlink $APP)")
getent hosts pje-fixture.test >/dev/null || echo "127.0.0.1 pje-fixture.test" >> /etc/hosts
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3 -subj /CN=pj18-generated-root -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj /CN=pje-fixture.test >/dev/null 2>&1
printf 'subjectAltName=DNS:pje-fixture.test\n' > san.ext
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 3 -extfile san.ext >/dev/null 2>&1
mkdir -p www && echo "hello from a generated server" > www/page.txt
python3 /pkg/tests/serve.py www srv.crt srv.key 8443 > server.log 2>&1 & S=$!
sleep 2
ORIG=$(sparky-pjeoffice status --json | python3 -c "import json,sys;print(json.load(sys.stdin)['state']['trust']['added'])")
echo "== red: the program's own list does not know the system's new authority"
$JAVA -Dpjeoffice_home=$APP -cp /classes:$APP/pjeoffice-pro.jar AppTrustProbe https://pje-fixture.test:8443/page.txt > probe-original.txt 2>&1; RC=$?
t "the program's HTTPS codec refuses the generated server (PKIX path building failed)" "[ $RC != 0 ] && grep -q -i 'PKIX\|unable to find valid certification path' probe-original.txt"
echo "== the system trusts it; the package makes the program's list again (what its dpkg trigger does when /etc/ssl/certs changes)"
cp ca.crt /usr/local/share/ca-certificates/pj18-generated-root.crt && update-ca-certificates > update-ca.txt 2>&1
sparky-pjeoffice trust --if-changed; RC=$?
NEW=$(sparky-pjeoffice status --json | python3 -c "import json,sys;print(json.load(sys.stdin)['state']['trust']['added'])")
t "the trust command exits 0 and adds exactly one certificate" "[ $RC = 0 ] && [ $NEW = $((ORIG + 1)) ]"
echo "== green: the merged list first on the class path"
$JAVA -Dpjeoffice_home=$APP -cp "/classes:$TRUST:$APP/pjeoffice-pro.jar" AppTrustProbe https://pje-fixture.test:8443/page.txt > probe-merged.txt 2>&1; RC=$?
t "the same codec now reads the page" "[ $RC = 0 ] && grep -q 'hello from a generated server' probe-merged.txt"
KT=$APP/jre/bin/keytool
$KT -list -v -keystore $TRUST/pjeoffice.jks -storetype PKCS12 -storepass pjeoffice 2>/dev/null | grep 'SHA256:' | sed 's/^[[:space:]]*//' | sort > fp-merged.txt
unzip -p $APP/pjeoffice-pro.jar pjeoffice.jks > original.p12
$KT -list -v -keystore original.p12 -storetype PKCS12 -storepass pjeoffice 2>/dev/null | grep 'SHA256:' | sed 's/^[[:space:]]*//' | sort > fp-original.txt
t "keytool: every one of the program's original certificates is still in the merged list" "[ \$(comm -23 fp-original.txt fp-merged.txt | wc -l) = 0 ] && [ \$(wc -l < fp-original.txt) = 168 ]"
t "keytool: the merged list is the originals plus the system's ($NEW added)" "[ \$(wc -l < fp-merged.txt) = \$((168 + NEW)) ]"
t "the restart is said to be pending only when a signer runs (none runs here)" "python3 -c \"import json;assert json.load(open('/var/lib/sparky-pjeoffice/state.json'))['restart_pending'] is False\""
kill $S 2>/dev/null
echo; [ $FAIL = 0 ] && echo "RESULT: PASS (trust)" || echo "RESULT: FAIL (trust)"
exit $FAIL
