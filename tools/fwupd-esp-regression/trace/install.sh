#!/bin/bash
# Arm for the next boot without reloading units or starting either daemon.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
UNIT=/etc/systemd/system/fwupd-esp-unmount-314-trace.service
DROPIN=/etc/systemd/system/fwupd.service.d/90-order314-trace.conf
SCRIPT=/usr/local/libexec/fwupd-esp-unmount-314-trace.py
LINK=/etc/systemd/system/multi-user.target.wants/fwupd-esp-unmount-314-trace.service
for file in "$UNIT" "$DROPIN" "$SCRIPT" "$LINK"; do
    [[ ! -e "$file" && ! -L "$file" ]] || { echo "Refusing to replace $file" >&2; exit 1; }
done
install -d /usr/local/libexec /etc/systemd/system/fwupd.service.d
install -m 0755 "$HERE/trace.py" "$SCRIPT"
install -m 0644 "$HERE/fwupd-esp-unmount-314-trace.service" "$UNIT"
install -m 0644 "$HERE/90-order314-trace.conf" "$DROPIN"
systemd-analyze verify "$UNIT" /usr/lib/systemd/system/fwupd.service
systemctl enable --no-reload fwupd-esp-unmount-314-trace.service
sha256sum "$UNIT" "$DROPIN" "$SCRIPT"
readlink "$LINK"
printf '%s\n' 'ARMED for the next boot; no daemon-reload and no service start performed.'
