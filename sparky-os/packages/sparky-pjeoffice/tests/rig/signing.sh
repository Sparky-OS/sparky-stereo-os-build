#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As the person (uid 1000) in a container that has sparky-pjeoffice installed from its .deb and CNJ's program fetched by it, no network, a private Xvfb:
# a generated identity (token-fixture.sh of tools/pjeoffice-audit), a PDF signed through the package's own `sparky-pjeoffice sign-pdf` (the Dolphin action's
# command) and a login challenge signed through the program's developer entry point, each verified OUTSIDE the program with OpenSSL.
# Usage: signing.sh MODE (file | softhsm) OUT   Needs: /tools (tools/pjeoffice-audit), /classes (its compiled helpers), /scratch (rw), this folder at /rig
set -u
MODE=${1:?file or softhsm}; OUT=${2:?result folder under /scratch}
ulimit -c 1
export DISPLAY=:99
mkdir -p "$OUT/shots"; cd /scratch
sh /tools/token-fixture.sh /scratch/identity > "$OUT/fixture.log" 2>&1 || { tail -5 "$OUT/fixture.log"; echo "FAIL fixture"; exit 1; }
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
XPID=$!
sleep 1
mkdir -p "$HOME/.pjeoffice-pro"
case $MODE in
file) printf 'list.a1=/scratch/identity/test.p12\n' > "$HOME/.pjeoffice-pro/pjeoffice-pro.config" ;;
softhsm) printf 'list.a3=/usr/lib/softhsm/libsofthsm2.so\n' > "$HOME/.pjeoffice-pro/pjeoffice-pro.config"; export SOFTHSM2_CONF=/scratch/identity/softhsm2.conf ;;
esac
JAVA=/opt/pjeoffice-pro/current/jre/bin/java
$JAVA -cp /classes:/opt/pjeoffice-pro/current/pjeoffice-pro.jar CreatePdf /scratch/identity/document.pdf
cp /scratch/identity/document.pdf "$OUT/document.pdf.original"
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }

STEPS=${STEPS:-"pdf login"}
if [[ " $STEPS " == *" pdf "* ]]; then
echo "== 1. a PDF through the package's own command ($MODE)"
python3 /rig/drive.py /scratch/identity/pin --shots "$OUT/shots" --seconds 150 > "$OUT/drive-pdf.log" 2>&1 & DRV=$!
sparky-pjeoffice sign-pdf --wait 75 /scratch/identity/document.pdf > "$OUT/sign-pdf.out" 2>&1; RC=$?
cp "$HOME/.local/state/sparky-pjeoffice/signer.log" "$OUT/signer.log" 2>/dev/null; ls -la /scratch/identity | grep -i -E 'pdf|p7' > "$OUT/identity-pdf-files.txt"
kill $DRV 2>/dev/null
t "sign-pdf exits 0" "[ $RC = 0 ]"
t "the CAdES file is beside the PDF" "[ -s /scratch/identity/document.pdf.p7s ]"
cp /scratch/identity/document.pdf.p7s "$OUT/document.pdf.p7s" 2>/dev/null
openssl cms -verify -inform DER -in "$OUT/document.pdf.p7s" -CAfile /scratch/identity/root.pem -purpose any -out "$OUT/extracted.pdf" > "$OUT/cms-verify.txt" 2>&1
t "openssl verifies the CMS against the generated root" "grep -q 'Verification successful' $OUT/cms-verify.txt"
t "the signed content is the original PDF, byte for byte" "cmp -s $OUT/extracted.pdf $OUT/document.pdf.original"
openssl cms -cmsout -print -inform DER -in "$OUT/document.pdf.p7s" > "$OUT/cms-print.txt" 2>&1
t "the signed attributes are there (contentType, signingTime, messageDigest)" "grep -q 'contentType' $OUT/cms-print.txt && grep -q 'signingTime' $OUT/cms-print.txt && grep -q 'messageDigest' $OUT/cms-print.txt"
# the negative control: another content under the same signature must fail
printf 'ALTERED' > "$OUT/altered.pdf"
openssl cms -verify -inform DER -in "$OUT/document.pdf.p7s" -CAfile /scratch/identity/root.pem -purpose any -content "$OUT/altered.pdf" -binary -out /dev/null > "$OUT/cms-altered.txt" 2>&1
t "negative control: an altered content is refused" "! grep -q 'Verification successful' $OUT/cms-altered.txt"
t "a signing that never finishes would have been told, not hidden: the person's problem list is empty" "[ -z \"\$(sparky-stereo-problems list --person 2>/dev/null | grep -i 'sparky-pjeoffice')\" ]"

fi
if [[ " $STEPS " == *" login "* ]]; then
echo "== 2. a login challenge (the program's developer entry point to a local backend)"
PID=$(cat "$HOME/.local/state/sparky-pjeoffice/signer.pid" 2>/dev/null); [ -n "$PID" ] && kill "$PID" 2>/dev/null; sleep 2
TRUST=/var/lib/sparky-pjeoffice/trust/$(basename "$(readlink /opt/pjeoffice-pro/current)")
(cd /opt/pjeoffice-pro/current && $JAVA -Dpjeoffice_home=/opt/pjeoffice-pro/current -Dffmpeg_home=/var/lib/sparky-pjeoffice/ffmpeg -Dsigner4j_a3auto=true -cp "/classes:$TRUST:/opt/pjeoffice-pro/current/pjeoffice-pro.jar" LocalTestMain > "$OUT/signer-dev.log" 2>&1 &)
for i in $(seq 40); do sparky-pjeoffice status --json | grep -q '"signer_answers": true' && break; sleep 1; done
python3 /tools/backend.py > "$OUT/backend.log" 2>&1 & BK=$!
python3 /rig/drive.py /scratch/identity/pin --click "Autorização de site:0.13:0.85" --shots "$OUT/shots" --seconds 100 > "$OUT/drive-login.log" 2>&1 & DRV=$!
python3 /tools/request.py login; sleep 3
kill $DRV $BK 2>/dev/null
cp /scratch/request-login-result.json "$OUT/" 2>/dev/null; cp /scratch/callback-0.* "$OUT/" 2>/dev/null
EXPECT=$([ $MODE = file ] && echo 2 || echo 1)
python3 /tools/verify-login.py 0 $EXPECT > "$OUT/verify-login.txt" 2>&1
t "the login signature, the PkiPath chain and the altered-challenge control verify outside the program" "grep -q '^PASS: application login signature' $OUT/verify-login.txt"
fi
kill $XPID 2>/dev/null
echo; [ $FAIL = 0 ] && echo "RESULT: PASS ($MODE)" || echo "RESULT: FAIL ($MODE)"
exit $FAIL
