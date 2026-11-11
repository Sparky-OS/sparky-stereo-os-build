#!/bin/bash
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
# Builds the plain authored candidate. Publication uses the edition's Lean Code pipeline.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
OUT=$(realpath "${OUT:?set OUT to an empty output folder}")
IMAGE=${IMAGE:-debian@sha256:cf15c569a84dfda832e421ab27a8049e962ba8e90571612396cd8db799279e4e}
sparky_provenance_init "$IMAGE"
docker run --rm --name fonts-519-build --platform linux/amd64 --ulimit core=0 \
    "${SPARKY_PROV_ARGS[@]}" -e OWNER="$(id -u):$(id -g)" \
    -v "$OUT:/out" -v "$HERE:/recipe:ro" \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v "$HERE/../../../tools/https-only-apt.sh:/run/https-only-apt.sh:ro" \
    "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
trap '\''chown -R "$OWNER" /out'\'' EXIT
apt-get update -qq
apt-get install -y --no-install-recommends build-essential debhelper po-debconf curl ca-certificates patch python3 dpkg-dev
cd /out
curl --fail --location --proto =https https://deb.debian.org/debian/pool/contrib/m/msttcorefonts/msttcorefonts_3.8.1.tar.xz -o msttcorefonts_3.8.1.tar.xz
echo "211f86e82b56cf87461da4bb21136b096a57ae70ed9bcb6eb27f34c407295bf3  msttcorefonts_3.8.1.tar.xz" | sha256sum -c -
tar -xf msttcorefonts_3.8.1.tar.xz
python3 /recipe/prepare.py /out/msttcorefonts-3.8.1
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /out/msttcorefonts-3.8.1
cd msttcorefonts-3.8.1
dpkg-buildpackage -us -uc -aamd64
'
