#!/bin/bash
set -euo pipefail
# Guest only. OVMF has no ESRT entries, so supply one synthetic capsule device.
install -d /opt/order314/sysfw/efi/efivars /opt/order314/sysfw/efi/esrt/entries/entry0
for item in /sys/firmware/efi/*; do
    name=${item##*/}
    case "$name" in efivars|esrt) continue;; esac
    ln -sfn "$item" "/opt/order314/sysfw/efi/$name"
done
mountpoint -q /opt/order314/sysfw/efi/efivars || mount --bind /sys/firmware/efi/efivars /opt/order314/sysfw/efi/efivars
entry=/opt/order314/sysfw/efi/esrt/entries/entry0
printf '%s\n' 11111111-2222-3333-4444-555555555555 > "$entry/fw_class"
for field in fw_version lowest_supported_fw_version; do printf '100\n' > "$entry/$field"; done
for field in capsule_flags last_attempt_status last_attempt_version; do printf '0\n' > "$entry/$field"; done
printf '1\n' > "$entry/fw_type"
systemctl start boot-efi.mount
findmnt /boot/efi
