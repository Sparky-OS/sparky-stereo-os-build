#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As root in a container made from the flat repository image (the packages are offered, sparky-pjeoffice is not installed, the app center is extracted from its .deb):
# the entry's page and its action, in four cases. Usage: entry.sh CASE OUT   CASE: page | good | wronghash | interrupted | switchfail
# Needs /debs (the built packages), /tb (the proof helpers), /fx (rw scratch), and the network only for the cases that fetch (good, wronghash).
set -u
CASE=${1:?}; OUT=${2:?}; mkdir -p "$OUT"
export DEBIAN_FRONTEND=noninteractive LANG=${LANG:-en_US.UTF-8}
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }
dpkg-deb -x /debs/sparky-aptus-stereo-appcenter_0.1.13+lc1_all.deb /
# the stand-in for NetworkManager's answer, the only thing replaced: METERED=yes|no
cat > /usr/local/bin/busctl <<'BC'
#!/bin/sh
case "${METERED:-no}" in yes) echo "u 1" ;; no) echo "u 2" ;; none) echo "no NM" >&2; exit 1 ;; esac
BC
chmod +x /usr/local/bin/busctl
# a system without the tools: OpenSC, pcscd and libccid are the package's Recommends
apt-get -y -q remove opensc pcscd libccid >/dev/null 2>&1
APP=/usr/lib/sparky-aptus-stereo-appcenter
page() { python3 -c "
import re,sys,html
t=sys.stdin.read(); t=re.sub(r'<script.*?</script>|<style.*?</style>','',t,flags=re.S); t=re.sub(r'</p>|<br ?/?>','\n',t); t=html.unescape(re.sub(r'<[^>]+>','',t))
body=t[t.find('PJeOffice Pro'):]
print('\n'.join(l.strip() for l in body.splitlines() if l.strip()))"; }
case $CASE in
page)
  for LNG in en_US.UTF-8 pt_BR.UTF-8; do
    for M in no yes none; do
      METERED=$M LANG=$LNG python3 $APP/main-entry pjeoffice --render | page > "$OUT/page-${LNG%%.*}-metered-$M.txt" 2>&1
    done
  done
  t "the card says the download from CNJ before the button, always" "grep -q '159.7 MiB' $OUT/page-en_US-metered-no.txt && grep -q 'pje-office.pje.jus.br' $OUT/page-en_US-metered-no.txt"
  t "it says apt's sizes for the package and what it brings" "grep -q 'Packages apt installs for this' $OUT/page-en_US-metered-no.txt"
  t "on a metered connection the shared notice comes with it" "grep -q 'metered' $OUT/page-en_US-metered-yes.txt"
  t "with NetworkManager unreadable the shared notice says so" "grep -q -i 'could not tell\|Could not tell' $OUT/page-en_US-metered-none.txt"
  t "the sentence is in Portuguese in pt_BR" "grep -q 'assinador' $OUT/page-pt_BR-metered-no.txt"
  t "the Install button is the entry's own link" "METERED=no python3 $APP/main-entry pjeoffice --render | grep -q 'aptus://debinst_pjeoffice'"
  ;;
good)
  METERED=yes python3 $APP/actions/entry pjeoffice install > "$OUT/action.txt" 2>&1; RC=$?
  t "the action exits 0" "[ $RC = 0 ]"
  t "the tools came with it: OpenSC, pcscd and libccid are installed" "dpkg -s opensc pcscd libccid 2>/dev/null | grep -c 'Status: install ok installed' | grep -q 3"
  t "the program is installed and in use" "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.16u ]"
  t "the action said the sizes before anything was fetched" "[ \$(grep -n 'Packages apt installs' $OUT/action.txt | head -1 | cut -d: -f1) -lt \$(grep -n 'Fetching PJeOffice Pro' $OUT/action.txt | head -1 | cut -d: -f1) ]"
  t "and the metered notice before that" "grep -q 'metered' $OUT/action.txt"
  METERED=no python3 $APP/main-entry pjeoffice --render | page > "$OUT/page-after-install.txt" 2>&1
  t "the page then offers the removal" "grep -q -i 'Installed' $OUT/page-after-install.txt && ! grep -q 'Packages apt installs' $OUT/page-after-install.txt"
  ;;
wronghash)
  python3 - <<'PY'
import json
p='/usr/share/sparky-pjeoffice/catalogue.json'
c=json.load(open(p)); v=c['versions'][c['current']]; v['sha256']=v['sha256'][:-1]+('0' if v['sha256'][-1]!='0' else '1')
json.dump(c,open(p,'w'),indent=1)
PY
  METERED=no python3 $APP/actions/entry pjeoffice install > "$OUT/action.txt" 2>&1; RC=$?
  t "the action fails" "[ $RC != 0 ]"
  t "it says the file is not the reviewed one, in the action's own output" "grep -q 'not the one that was reviewed' $OUT/action.txt"
  t "nothing of the program is left" "[ ! -e /opt/pjeoffice-pro/current ] && [ ! -e /var/cache/sparky-pjeoffice/pjeoffice-pro-2.5.16u.zip ]"
  python3 $APP/main-entry pjeoffice --render | page > "$OUT/page-after-failure.txt" 2>&1
  t "the page shows the same sentence" "grep -q 'not the one that was reviewed' $OUT/page-after-failure.txt"
  t "the engine keeps the problem with a repair" "sparky-stereo-problems list sparky-pjeoffice | grep -q 'Repair: /usr/bin/sparky-pjeoffice install'"
  dpkg -s sparky-pjeoffice 2>/dev/null | grep '^Status' > "$OUT/dpkg-status.txt"
  ;;
interrupted|switchfail)
  # the fixture's server and certificate authority (loopback only), as tests/installer.sh makes them
  FX=/fx; cd $FX
  getent hosts pje-fixture.test >/dev/null || echo "127.0.0.1 pje-fixture.test" >> /etc/hosts
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3 -subj /CN=pj18-fixture-ca >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj /CN=pje-fixture.test >/dev/null 2>&1
  printf 'subjectAltName=DNS:pje-fixture.test\n' > san.ext
  openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 3 -extfile san.ext >/dev/null 2>&1
  cp ca.crt /usr/local/share/ca-certificates/pj18-fixture-ca.crt && update-ca-certificates >/dev/null 2>&1
  python3 /pkg/tests/make-fixture.py $FX/www 2.5.90u >/dev/null
  python3 /pkg/tests/make-fixture.py $FX/www 2.5.92u --bad-java >/dev/null
  python3 /pkg/tests/serve.py $FX/www srv.crt srv.key 8443 > server.log 2>&1 & S1=$!
  python3 /pkg/tests/serve.py $FX/www srv.crt srv.key 8444 --cut-at 3000 > server-cut.log 2>&1 & S2=$!
  sleep 2
  if [ $CASE = interrupted ]; then
    python3 - <<'PY'
import json
c=json.load(open('/fx/www/catalogue-2.5.90u.json')); c['versions']['2.5.90u']['url']=c['versions']['2.5.90u']['url'].replace(':8443',':8444')
json.dump(c,open('/usr/share/sparky-pjeoffice/catalogue.json','w'),indent=1)
PY
    METERED=no python3 $APP/actions/entry pjeoffice install > "$OUT/action.txt" 2>&1; RC=$?
    t "the action fails" "[ $RC != 0 ]"
    t "it says the download could not be fetched and what to do" "grep -q 'could not be fetched from CNJ' $OUT/action.txt && grep -q 'Repair' $OUT/action.txt"
    t "the part is kept for the next try" "[ -s /var/cache/sparky-pjeoffice/pjeoffice-pro-2.5.90u.zip.part ]"
    t "nothing is installed" "[ ! -e /opt/pjeoffice-pro/current ]"
    cp /fx/www/catalogue-2.5.90u.json /usr/share/sparky-pjeoffice/catalogue.json
    # the person's Repair (what the Problems page runs) on a good connection
    sparky-stereo-problems repair --machine sparky-pjeoffice > "$OUT/repair.txt" 2>&1; RC=$?
    t "Repair resumes the download and installs" "[ $RC = 0 ] && [ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ] && grep -q 'Resuming an earlier download' $OUT/repair.txt"
    t "the problem is gone" "! sparky-stereo-problems list sparky-pjeoffice | grep -q failed"
  else
    cp /fx/www/catalogue-2.5.90u.json /usr/share/sparky-pjeoffice/catalogue.json
    sparky-pjeoffice install > "$OUT/first.txt" 2>&1
    t "version 2.5.90u is installed first" "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
    cp /fx/www/catalogue-2.5.92u.json /usr/share/sparky-pjeoffice/catalogue.json
    # what apt runs after an update's unpack: the package's own setup, here as a reinstall of the same package
    apt-get -y --reinstall install sparky-pjeoffice > "$OUT/apt-reinstall.txt" 2>&1; RC=$?
    t "apt completes: the failed update keeps the version in use, and says so" "[ $RC = 0 ] && grep -q 'did not install; the version that was in use still is' $OUT/apt-reinstall.txt"
    t "the version in use is still 2.5.90u" "[ \"\$(readlink /opt/pjeoffice-pro/current)\" = versions/2.5.90u ]"
    t "the engine keeps the reason, naming the version in use" "sparky-stereo-problems list sparky-pjeoffice | grep -q 'version 2.5.90u is still in use'"
    t "the signer's program folder of the failed version is not left" "[ ! -d /opt/pjeoffice-pro/versions/2.5.92u ] && [ -z \"\$(ls -d /opt/pjeoffice-pro/versions/.*new 2>/dev/null)\" ]"
  fi
  kill $S1 $S2 2>/dev/null
  ;;
esac
echo; [ $FAIL = 0 ] && echo "RESULT: PASS ($CASE)" || echo "RESULT: FAIL ($CASE)"
exit $FAIL
