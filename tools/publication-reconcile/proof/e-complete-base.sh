#!/bin/bash
# SPDX-License-Identifier: MIT
# Finish a recorded published-dpkg bootstrap with the corrected package set.
. /proof/proof-common.sh
. /proof/proof-checks.sh
trap 'chown -R 1000:1000 /out' EXIT
edition /base
check_edition_dpkg 'published bootstrap before the requested package set'
update_all "$O/e1-complete-update.log"
apt_get -y -q --no-install-recommends install ${E_PACKAGES:?} > "$O/e1-complete-install.log" 2>&1 || fail 'published baseline package installation failed'
for p in $E_PACKAGES; do
    status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$p")
    [[ "$status" == ii* ]] || fail "baseline requested package is not configured: $p ($status)"
done
snapshot "$O/e1-snapshot.txt"
dpkg --audit > "$O/e1-audit.txt" 2>&1
[ ! -s "$O/e1-audit.txt" ] || fail 'published baseline audit is not empty'
pass 'published baseline requested package set is installed and dpkg audit is empty'
apt_get clean
