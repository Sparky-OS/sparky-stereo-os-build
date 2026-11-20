#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Generate a disposable identity and verify the software-token fixture in a container.
set -eu
umask 077
fixture=${1:?new scratch directory}
mkdir "$fixture"
cd "$fixture"
fixture=$(pwd)
mkdir tokens
printf 'directories.tokendir = %s/tokens\nobjectstore.backend = file\nlog.level = ERROR\n' "$fixture" > softhsm2.conf
export SOFTHSM2_CONF="$fixture/softhsm2.conf"
python3 - <<'PY'
from pathlib import Path
import secrets
Path('pin').write_text(secrets.token_hex(8))
Path('so-pin').write_text(secrets.token_hex(8))
PY
PIN=$(cat pin); SO_PIN=$(cat so-pin); export PIN
softhsm2-util --init-token --free --label TEST-ONLY --pin "$PIN" --so-pin "$SO_PIN" > init.log
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=TEST ONLY ROOT' -keyout root.key -out root.pem > generation.log 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj '/CN=SIGNER TEST ONLY' -keyout key.pem -out leaf.csr >> generation.log 2>&1
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,nonRepudiation\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\nsubjectAltName=otherName:2.16.76.1.3.1;UTF8:000000000000000000000000000000000000000000000000000\n' > leaf.ext
openssl x509 -req -in leaf.csr -CA root.pem -CAkey root.key -CAcreateserial -days 2 -extfile leaf.ext -out cert.pem >> generation.log 2>&1
openssl verify -CAfile root.pem cert.pem
openssl pkcs8 -topk8 -nocrypt -in key.pem -out key-p8.pem
softhsm2-util --import key-p8.pem --token TEST-ONLY --label TEST-KEY --id 01 --pin "$PIN" > import.log
openssl x509 -in cert.pem -outform DER -out cert.der
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label TEST-ONLY --login --pin env:PIN --write-object cert.der --type cert --id 01 --label TEST-CERT > cert-import.log 2>&1
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --list-slots
printf 'SYNTHETIC TEST CHALLENGE\n' > challenge
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label TEST-ONLY --login --pin env:PIN --sign --mechanism SHA256-RSA-PKCS --id 01 --input-file challenge --output-file signature > sign.log 2>&1
openssl x509 -in cert.pem -pubkey -noout > public.pem
openssl dgst -sha256 -verify public.pem -signature signature challenge
printf 'ALTERED TEST CHALLENGE\n' > wrong-challenge
if openssl dgst -sha256 -verify public.pem -signature signature wrong-challenge > negative.log 2>&1; then
    echo 'FAIL: an altered challenge verified' >&2
    exit 1
fi
echo 'PASS: altered challenge refused'
openssl pkcs12 -export -inkey key.pem -in cert.pem -certfile root.pem -out test.p12 -passout file:pin
echo 'Fixture only: no PJeOffice request has been signed by this script.'
