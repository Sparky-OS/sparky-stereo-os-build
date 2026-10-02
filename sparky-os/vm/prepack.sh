#!/bin/bash
# Cleans the development VM right before sparkybackup packs the ISO (Daniel, 2026-10-02):
# no temp files, no package lists, no caches in the image.
# Run as root in the VM:
#   sparky-vm.sh ssh 'sudo bash /srv/sparky-os/vm/prepack.sh [--final]'
# --final also removes what only the development VM needs (passwordless sudo, our file:
# repository line, the SSH server we drive it with) and resets the machine-id: run it last,
# then sparkybackup, then power off.
# Defragmenting is not needed: mksquashfs writes every file fresh, compressed and contiguous,
# so the VM's fragmentation never reaches the ISO. What helps from outside is compacting the
# VM's disk after TRIM (compact-disk on the host, see sparky-vm.sh's notes).
set -u
FINAL=${1:-}
USERNAME=$(getent passwd 1000 | cut -d: -f1)
export DEBIAN_FRONTEND=noninteractive

echo "== command-not-found index (needs the package lists, so before cleaning them)"
apt-get -q update >/dev/null
update-command-not-found 2>/dev/null || true

echo "== BleachBit, system (not system.localizations: the edition ships every language)"
bleachbit --clean apt.autoclean apt.autoremove apt.clean apt.package_lists \
	bash.history journald.clean system.cache system.rotated_logs system.tmp system.trash \
	x11.debug_logs

echo "== BleachBit, $USERNAME"
sudo -u "$USERNAME" bleachbit --clean bash.history chromium.cache chromium.history \
	chromium.session chromium.crash_reports firefox.cache firefox.crash_reports \
	firefox.session firefox.url_history firefox.forms gimp.tmp java.cache kde.cache \
	kde.recent_documents kde.tmp libreoffice.history system.recent_documents system.trash \
	thumbnails.cache vlc.mru wine.tmp

echo "== TRIM, so the VM's disk can give the freed space back"
fstrim -av

if [ "$FINAL" = "--final" ]; then
	echo "== development-only leftovers"
	rm -f /etc/sudoers.d/90-sparky-dev
	rm -f /etc/apt/sources.list.d/sparky-stereo.list   # the file: repository; the published one replaces it
	apt-get -y -q purge openssh-server >/dev/null
	truncate -s 0 /etc/machine-id
	rm -f /var/lib/dbus/machine-id
	echo "done: run sparkybackup now (this shell keeps root), then power off"
fi
