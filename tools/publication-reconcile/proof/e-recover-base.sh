#!/bin/bash
# SPDX-License-Identifier: MIT
# Resume an explicitly recorded baseline checkpoint after missing bootstrap tools.
# This is not a successful baseline until its database, requested packages and audit pass.
. /proof/proof-common.sh
. /proof/proof-checks.sh
trap 'chown -R 1000:1000 /out' EXIT
edition /base
update_all "$O/recovery-update.log" || fail 'baseline archive update failed'
snapshot "$O/recovery-before.txt"
apt-cache policy cpio zstd > "$O/recovery-bootstrap-policy.txt"
mkdir -p /tmp/baseline-bootstrap
cd /tmp/baseline-bootstrap
# Download/unpack first: an interrupted database can need cpio before configure -a.
apt_get download cpio zstd > "$O/recovery-download.log" 2>&1
sha256sum ./*.deb > "$O/recovery-bootstrap-sha256.txt"
dpkg --unpack ./*.deb > "$O/recovery-unpack.log" 2>&1
dpkg --configure -a > "$O/recovery-configure.log" 2>&1
apt_get -y --no-install-recommends -f install > "$O/recovery-fix.log" 2>&1
setup_sources
check_edition_dpkg 'recovered published baseline'
for p in ${E_PACKAGES:?set the recorded baseline package set}; do
    status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$p")
    [[ "$status" == ii* ]] || fail "baseline requested package is not configured: $p ($status)"
done
snapshot "$O/e1-snapshot.txt"
dpkg --audit > "$O/e1-audit.txt" 2>&1
[ ! -s "$O/e1-audit.txt" ] || fail 'recovered baseline audit is not empty'
pass 'recovered baseline requested package set is installed and dpkg audit is empty'
apt_get clean
