#!/bin/bash
# the SparkyLinux main app center's install block (the fork's branch order18b-sparkylinux) run as root with the real file from CNJ, then with one digit of the SHA-256 changed
set -u
REPO=/ac2
BLOCK=$(awk '/^elif \[ "\$PACKAGE" = "pjeoffice" \]; then$/{f=1} f&&/^elif \[ "\$PACKAGE" = "vinci" \]; then$/{exit} f{print}' $REPO/9/lib/sparky-aptus-appcenter/bin/aptus-package-install)
VARS=$(grep -E '^(SERVERPJEOFFICE|PACKPJEOFFICE|SHAPJEOFFICE|SIZEPJEOFFICE)=' $REPO/9/lib/sparky-aptus-appcenter/bin/aptus-package-install)
run() {  # $1 = label, $2 = sha override
  rm -rf /opt/pjeoffice-pro /tmp/sparky-appcenter
  cat > /tmp/harness.sh <<H
$VARS
[ -n "\${SHAOVERRIDE:-}" ] && SHAPJEOFFICE=\$SHAOVERRIDE
WORKDIR=/tmp/sparky-appcenter
INSTALL="apt-get install"
SPARKYXTERM="bash -c"
PACKAGE=pjeoffice
if false; then true
$BLOCK
fi
H
  SHAOVERRIDE=$2 bash /tmp/harness.sh > /out/$1.txt 2>&1; echo "rc=$?" >> /out/$1.txt
}
run real ""
echo "== real file from CNJ"; grep -E "installed in|NOT|rc=" /out/real.txt | head
[ -f /opt/pjeoffice-pro/pjeoffice-pro.jar ] && echo "PASS  /opt/pjeoffice-pro/pjeoffice-pro.jar exists" || echo "FAIL  not installed"
grep -q '^update.url=disabled' /opt/pjeoffice-pro/pjeoffice-update.properties && echo "PASS  updater switched off" || echo "FAIL  updater"
/opt/pjeoffice-pro/jre/bin/java -version 2>&1 | head -1
[ -x /usr/bin/pjeoffice-pro ] && echo "PASS  /usr/bin/pjeoffice-pro link" ; [ -f /usr/share/applications/pjeoffice-pro.desktop ] && echo "PASS  menu entry"
run wrong "0000000000000000000000000000000000000000000000000000000000000000"
echo "== a SHA-256 that is not the file's"; grep -E "NOT|rc=" /out/wrong.txt | head -3
[ ! -e /opt/pjeoffice-pro ] && echo "PASS  nothing installed after the mismatch" || echo "FAIL  installed despite the mismatch"
