#!/bin/bash
# Makes the UEFI variable stores the boot matrix uses. Run fw/fetch-fw.py first; virt-fw-vars (python3-virt-firmware) must be on PATH.
# Only python3-virt-firmware's virt-fw-vars is used; the firmware files are the unpacked packages.
set -e
cd "$(dirname "$(readlink -f "$0")")"
O64=ovmf-forky/usr/share/OVMF
O32=ovmf32-trixie/usr/share/OVMF
V=vars
mkdir -p $V
cp $O64/OVMF_VARS_4M.fd $V/x64-empty.vars                       # Secure Boot off
cp $O64/OVMF_VARS_4M.ms.fd $V/x64-ms-default.vars               # Secure Boot on; Microsoft 2011 + 2023 keys (distribution default)
virt-fw-vars -i $V/x64-ms-default.vars -o $V/x64-ms-default-sbat2024.vars --set-sbat-level $V/sbat-2024-08-windows.txt
virt-fw-vars -i $V/x64-ms-default.vars -o $V/x64-ms-default-sbatlax.vars --set-sbat-level $V/sbat-lax-2099.txt   # A/B control: a dated-ahead level with no revocations
# a machine whose db has only the old Microsoft UEFI CA (2011), and one with only the new one (2023)
mkdir -p $V/certs && (cd $V/certs && virt-fw-vars -i ../x64-ms-default.vars --extract-certs >/dev/null 2>&1)
MSGUID=77fa9abd-0359-4d32-bd60-28f4e78f784b
virt-fw-vars -i $O64/OVMF_VARS_4M.fd -o $V/x64-ms-2011only.vars --enroll-generate bootmatrix-test --microsoft-db none --microsoft-kek none \
  --add-db $MSGUID $V/certs/db-$MSGUID-MicrosoftCorporationUEFICA2011.pem \
  --add-kek $MSGUID $V/certs/KEK-$MSGUID-MicrosoftCorporationKEKCA2011.pem --sb
virt-fw-vars -i $O64/OVMF_VARS_4M.fd -o $V/x64-ms-2023only.vars --enroll-generate bootmatrix-test --microsoft-db uefi23 --microsoft-kek 2023 --sb
cp $O32/OVMF32_VARS_4M.fd $V/ia32-empty.vars
for f in x64-ms-default-sbat2024 x64-ms-2011only x64-ms-2023only; do
  echo "=== $f"; virt-fw-vars -i $V/$f.vars -pv 2>&1 | grep -v '^INFO' | grep -E "^name|subject|SbatLevel|SecureBoot|SetupMode" | cut -c1-160
done
