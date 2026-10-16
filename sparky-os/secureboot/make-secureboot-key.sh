#!/bin/sh
# Makes a distribution's own Secure Boot signing key: an X.509 Machine Owner Key (MOK) that
# signs its kernel images (sbsign) and kernel modules, enrolled once by the user with mokutil.
# Usage: make-secureboot-key.sh "<common name>" "<organisation>" <private folder>
# The private key never leaves <private folder> (mode 700, key 600). Only cert.der (for
# `mokutil --import`) and cert.pem (for signing tools and the kernel's keyring) are shared.
set -eu
[ $# -eq 3 ] || { echo "usage: $0 \"<common name>\" \"<organisation>\" <private folder>" >&2; exit 2; }
CN=$1; O=$2; OUT=$3
OPENSSL=$(command -v /usr/bin/openssl || command -v openssl)
[ -e "$OUT/key.pem" ] && { echo "$OUT already holds a key; refusing to make another" >&2; exit 1; }
umask 077
mkdir -p "$OUT"; chmod 700 "$OUT"
cat > "$OUT/openssl.cnf" <<CNF
[ req ]
default_bits = 2048
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
# code signing only: shim refuses a db or MOK certificate whose extended key usage includes the
# Linux module signing purpose (1.3.6.1.4.1.2312.16.1.2, verify_eku in shim's verify.c), so such a
# key could not boot a kernel; the kernel itself checks no key usage for modules
extendedKeyUsage = codeSigning
CNF
"$OPENSSL" req -new -x509 -nodes -utf8 -sha256 -days 3650 -config "$OUT/openssl.cnf" \
	-newkey rsa:2048 -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
"$OPENSSL" x509 -in "$OUT/cert.pem" -outform DER -out "$OUT/cert.der"
chmod 600 "$OUT/key.pem"; chmod 644 "$OUT/cert.pem" "$OUT/cert.der" "$OUT/openssl.cnf"
"$OPENSSL" x509 -in "$OUT/cert.pem" -noout -subject -enddate -fingerprint -sha256
