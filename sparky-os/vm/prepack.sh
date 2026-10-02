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

echo "== $USERNAME: edition default look (sparkybackup copies the user's dotfiles into /etc/skel)"
# The VM user chose Breeze Light while testing; whatever sits in the user's own config would
# reach the ISO and override /etc/xdg. lookandfeeltool needs no running session: with a private
# D-Bus and the offscreen platform it moves the theme settings into ~/.config/kdedefaults (where
# Plasma 6 keeps a global theme's values) and removes the user's own overrides of them
# (ColorScheme, icons, cursor, Plasma style, splash, window decoration). It leaves
# widgetStyle in kdeglobals when the style is not available to it, so that key is deleted too
# (the edition's /etc/xdg/kdeglobals sets qt6ct-style). Checked 2026-10-02 in a debian:testing
# container with a user set to Breeze Light: every override gone, kdedefaults = OxygenDark.
LOOK=org.sparkystereo.desktop
UHOME=$(getent passwd "$USERNAME" | cut -d: -f6)
RT=$(mktemp -d /run/prepack-look.XXXXXX); chown "$USERNAME" "$RT"; chmod 700 "$RT"
sudo -u "$USERNAME" env HOME="$UHOME" XDG_RUNTIME_DIR="$RT" QT_QPA_PLATFORM=offscreen \
	dbus-run-session -- lookandfeeltool -a "$LOOK" >/dev/null 2>&1 \
	|| echo "WARNING: lookandfeeltool failed for $USERNAME; set $LOOK by hand before packing"
rmdir "$RT" 2>/dev/null || rm -rf "$RT"
sudo -u "$USERNAME" env HOME="$UHOME" kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle --delete
sudo -u "$USERNAME" env HOME="$UHOME" kwriteconfig6 --file kdeglobals --group General --key ColorScheme --delete
if grep -qx 'ColorScheme=OxygenDark' "$UHOME/.config/kdedefaults/kdeglobals" 2>/dev/null; then
	echo "ok: $USERNAME follows $LOOK (kdedefaults ColorScheme=OxygenDark)"
else
	echo "WARNING: $UHOME/.config/kdedefaults/kdeglobals does not say OxygenDark; check the look before packing"
fi

echo "== TRIM, so the VM's disk can give the freed space back"
fstrim -av

if [ "$FINAL" = "--final" ]; then
	echo "== development-only leftovers"
	rm -f /etc/sudoers.d/90-sparky-dev
	# the build-time hold on NVIDIA's packages (provision.sh); the hardware setup installs
	# them per machine
	rm -f /etc/apt/preferences.d/90sparky-stereo-nvidia
	# emulators install from APTus Stereo AppCenter, never from the ISO (Daniel and Paweł)
	mapfile -t emu < <(grep -v '^#' /srv/sparky-os/lists/emulation-3d.list | grep .)
	apt-get -y -q purge "${emu[@]}" >/dev/null
	rm -f /etc/apt/sources.list.d/sparky-stereo.list   # the file: repository; the published one replaces it
	apt-get -y -q purge openssh-server >/dev/null
	truncate -s 0 /etc/machine-id
	rm -f /var/lib/dbus/machine-id
	echo "done: run sparkybackup now (this shell keeps root), then power off"
fi
