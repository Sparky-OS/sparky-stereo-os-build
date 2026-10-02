#!/bin/bash
# Second step of the development VM's provisioning, after provision.sh: our own Sparky
# Stereo repository with its pins, the packages that failed, and the edition's packages.
# Run as root in the VM:
#   sparky-vm.sh ssh 'sudo systemd-run --unit=sparky-provision-2 --collect bash /srv/sparky-os/vm/provision-2.sh'
set -uo pipefail
mkdir -p /srv/sparky-work/logs
LOG=/srv/sparky-work/logs/provision-2-$(date +%Y%m%d-%H%M%S).log
exec >>"$LOG" 2>&1
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
echo "== start $(date -Is)"

# Our repository (unsigned while developing) and the edition's apt pins.
echo 'deb [trusted=yes] file:/srv/sparky-work/repo ./' >/etc/apt/sources.list.d/sparky-stereo.list
cp /srv/sparky-os/apt/90sparky-stereo-repo /srv/sparky-os/apt/90sparky-stereo-ffmpeg /etc/apt/preferences.d/
"${APT[@]}" update
# Our pinned stack (KWin, KScreen, libkscreen) replaces Debian's.
"${APT[@]}" full-upgrade || echo "!! full-upgrade"

# The packages provision.sh logged as failed, again (the FFmpeg pin and the carried
# libcapi20 fix Blender and Wine).
last=$(ls -t /srv/sparky-work/logs/provision-2*.log /srv/sparky-work/logs/provision-*.log 2>/dev/null | grep -v 'provision-2-' | head -1)
mapfile -t failed < <(grep -o -E '^!! [a-z0-9-]+: \S+' "$last" | awk '{print $3}' | sort -u)
echo "== retry ${#failed[@]}: ${failed[*]:-none}"
for p in "${failed[@]}"; do "${APT[@]}" install "$p" >/dev/null 2>&1 && echo "ok $p" || echo "!! still failing: $p"; done

# The edition's own packages and our stereo kernel (sparkybackup takes the running kernel
# into the ISO, so the VM boots it before packing).
"${APT[@]}" install sparky-stereo-look sparky-stereo-look-sparkyblack sparky-stereo-look-qplatinum \
	sparky-stereo-console sparky-stereo-info pipewire-bluez5-codec-aac \
	linux-image-7.3.0-rc1-stereo3d linux-headers-7.3.0-rc1-stereo3d || echo "!! edition packages"
"${APT[@]}" autoremove --purge
echo "== done $(date -Is)"
