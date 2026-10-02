#!/bin/bash
# Installs the edition's package lists in the development VM. Run as root in the VM:
#   sparky-vm.sh ssh 'sudo systemd-run --unit=sparky-provision --collect bash /srv/sparky-os/vm/provision.sh'
# The log lands on the host in /K3D/temp/sparky-os/logs/.
set -uo pipefail
LISTS=/srv/sparky-os/lists
mkdir -p /srv/sparky-work/logs
LOG=/srv/sparky-work/logs/provision-$(date +%Y%m%d-%H%M%S).log
exec >>"$LOG" 2>&1
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
echo "== start $(date -Is)"

# apt policy of the edition: Recommends and Suggests (Daniel, 2026-10-02); i386 for Steam,
# Wine and the 32-bit runtimes.
dpkg --add-architecture i386
cat >/etc/apt/apt.conf.d/90sparky-stereo <<CONF
APT::Install-Recommends "true";
APT::Install-Suggests "true";
CONF
# NVIDIA's closed driver is the hardware setup's choice per machine (our package brings
# NVIDIA's open modules); keep it out of the base build, Suggests included.
cat >/etc/apt/preferences.d/90sparky-stereo-nvidia <<PREF
Package: nvidia-driver* nvidia-kernel-* nvidia-tesla-* *nvidia-legacy* nvidia-settings* xserver-xorg-video-nvidia*
Pin: release *
Pin-Priority: -1
PREF
# Licence questions the build answers so the run doesn't stop; end users still accept
# Steam's agreement in the client itself.
debconf-set-selections <<SEL
steam steam/question select I AGREE
steam steam/license note
steam-installer steam/question select I AGREE
steam-installer steam/license note
ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula boolean true
SEL

"${APT[@]}" update
"${APT[@]}" full-upgrade || echo "!! full-upgrade failed"

failed=()
for l in look runtimes languages hardware system apps gaming games emulation-3d; do
	mapfile -t pkgs < <(grep -v '^#' "$LISTS/$l.list" | grep .)
	echo "== $l: ${#pkgs[@]} packages $(date -Is)"
	if ! "${APT[@]}" install "${pkgs[@]}"; then
		echo "!! $l as a whole failed; one by one"
		for p in "${pkgs[@]}"; do
			"${APT[@]}" install "$p" >/dev/null 2>&1 || { echo "!! $l: $p"; failed+=("$l:$p"); }
		done
	fi
done
mapfile -t rm < <(grep -v '^#' "$LISTS/base-remove.list" | grep .)
"${APT[@]}" purge "${rm[@]}" || echo "!! purge failed"
"${APT[@]}" autoremove --purge
echo "== failed (${#failed[@]}): ${failed[*]:-none}"
echo "== done $(date -Is)"
