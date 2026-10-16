#!/bin/sh
# Issues a new certificate for an existing Secure Boot key, with code signing as its only extended key
# usage, and keeps the old certificate beside it (cert.pem.<date>, cert.der.<date>). The private key does
# not change. Certificates made by make-secureboot-key.sh before 2026-10-15 also named the Linux module
# signing purpose (1.3.6.1.4.1.2312.16.1.2), and shim refuses such a certificate for boot images (verify_eku
# in shim's verify.c): a kernel signed with that key does not boot through shim, even with the certificate
# enrolled. After this, sign the kernels and modules again and enrol the new cert.der.
# Usage: reissue-cert.sh <private key folder> "<common name>" "<organisation>"
set -eu
[ $# -eq 3 ] || { echo "usage: $0 <private key folder> \"<common name>\" \"<organisation>\"" >&2; exit 2; }
D=$1; CN=$2; O=$3
OPENSSL=$(command -v /usr/bin/openssl || command -v openssl)
[ -e "$D/key.pem" ] || { echo "no key.pem in $D" >&2; exit 1; }
umask 077
stamp=$(date -u +%Y%m%d%H%M%S)
cat > "$D/openssl-reissue.cnf" <<CNF
[ req ]
distinguished_name = dn
prompt = no
string_mask = utf8only
x509_extensions = ext
[ dn ]
CN = $CN
O = $O
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
extendedKeyUsage = codeSigning
CNF
[ -e "$D/cert.pem" ] && cp -p "$D/cert.pem" "$D/cert.pem.$stamp"
[ -e "$D/cert.der" ] && cp -p "$D/cert.der" "$D/cert.der.$stamp"
"$OPENSSL" req -new -x509 -utf8 -sha256 -days 3650 -config "$D/openssl-reissue.cnf" -key "$D/key.pem" -out "$D/cert.pem.new"
"$OPENSSL" x509 -in "$D/cert.pem.new" -outform DER -out "$D/cert.der.new"
mv "$D/cert.pem.new" "$D/cert.pem"; mv "$D/cert.der.new" "$D/cert.der"
chmod 644 "$D/cert.pem" "$D/cert.der"
"$OPENSSL" x509 -in "$D/cert.pem" -noout -subject -enddate -fingerprint -sha256 -ext extendedKeyUsage
