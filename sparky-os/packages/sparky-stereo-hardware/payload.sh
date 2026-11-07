#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/07
set -euo pipefail
# Both system units name this installed documentation.
install -Dm644 "$HERE/README.md" "$D/usr/share/doc/sparky-stereo-hardware/README.md"
install -Dm755 "$HERE/bin/sparky-stereo-hardware" "$D/usr/bin/sparky-stereo-hardware"
# NVIDIA's i386 libraries when i386 comes after NVIDIA's driver: dpkg's post-invoke hook checks after every dpkg run
install -Dm755 "$HERE/bin/sparky-stereo-nvidia-i386" "$D/usr/lib/sparky-stereo-hardware/nvidia-i386"
install -Dm644 "$HERE/share/dpkg/sparky-stereo-hardware" "$D/etc/dpkg/dpkg.cfg.d/sparky-stereo-hardware"
# thermald stays on an Intel machine that has it from an earlier image (ORDER 43): marked manual once, after the apt run
install -Dm755 "$HERE/bin/sparky-stereo-thermald-manual" "$D/usr/lib/sparky-stereo-hardware/thermald-manual"
install -Dm644 "$HERE/share/systemd/sparky-stereo-hardware-thermald-manual.service" "$D/usr/lib/systemd/system/sparky-stereo-hardware-thermald-manual.service"
# the unit the hook starts inside an apt run: it installs them once that run has ended, under the engine
install -Dm644 "$HERE/share/systemd/sparky-stereo-hardware-nvidia-i386.service" "$D/usr/lib/systemd/system/sparky-stereo-hardware-nvidia-i386.service"
# told once: the unit's own step keeps its failure in the engine (with apt's output and the Repair), so the engine's
# handler for every failed service is masked for it by name, as the engine masks it for its own handler (an empty
# OnFailure= cannot remove a dependency another drop-in added: measured with systemd 262)
mkdir -p "$D/usr/lib/systemd/system/sparky-stereo-hardware-nvidia-i386.service.d"
ln -s /dev/null "$D/usr/lib/systemd/system/sparky-stereo-hardware-nvidia-i386.service.d/50-sparky-stereo-problems.conf"
# a Bluetooth adapter that cannot carry voice is told to the person, once, by the engine (ORDER 133): at boot and when an adapter appears or goes
install -Dm755 "$HERE/bin/sparky-stereo-bt-voice-check" "$D/usr/lib/sparky-stereo-hardware/bt-voice-check"
install -Dm644 "$HERE/share/systemd/sparky-stereo-hardware-bt-voice.service" "$D/usr/lib/systemd/system/sparky-stereo-hardware-bt-voice.service"
install -Dm644 "$HERE/share/udev/71-sparky-stereo-bt-voice.rules" "$D/usr/lib/udev/rules.d/71-sparky-stereo-bt-voice.rules"
# a newly connected headset or speaker (Bluetooth, or USB) takes the sound and hands it back when it leaves; the script is wanted, not required (ORDER 129)
install -Dm644 "$HERE/share/wireplumber/50-sparky-stereo-new-output.conf" "$D/usr/share/wireplumber/wireplumber.conf.d/50-sparky-stereo-new-output.conf"
install -Dm644 "$HERE/share/wireplumber/sparky-stereo-new-output.lua" "$D/usr/share/wireplumber/scripts/sparky-stereo-new-output.lua"
mkdir -p "$D/usr/lib/sparky-stereo-hardware" "$D/usr/share/sparky/sparky-stereo-hardware"
install -m644 "$HERE"/lib/* "$D/usr/lib/sparky-stereo-hardware/"
install -m644 "$HERE"/lang/* "$HERE/share/nvidia-open.ids" "$HERE/share/network-ids.tsv" "$HERE/share/nvidia-open-source.txt" "$HERE/share/rig-devices.json" "$D/usr/share/sparky/sparky-stereo-hardware/"
# NVIDIA's 580 branch (Maxwell, Pascal, Volta) and the older branches, from NVIDIA's 615.71.09 README (nvidia-legacy-source.txt)
install -m644 "$HERE/share/nvidia-legacy-580xx.ids" "$HERE/share/nvidia-legacy-older.tsv" "$HERE/share/nvidia-legacy-source.txt" "$D/usr/share/sparky/sparky-stereo-hardware/"
install -Dm644 "$HERE/share/sparky-stereo-hardware.desktop" "$D/usr/share/applications/sparky-stereo-hardware.desktop"
install -Dm644 "$HERE/share/org.sparky-stereo-hardware.policy" "$D/usr/share/polkit-1/actions/org.sparky-stereo-hardware.policy"
install -Dm644 "$HERE/share/apt/sparky-stereo-gpu-nvidia" "$D/etc/apt/preferences.d/sparky-stereo-gpu-nvidia"
install -Dm644 "$HERE/share/apt/sparky-stereo-gpu-amd" "$D/etc/apt/preferences.d/sparky-stereo-gpu-amd"
install -Dm755 "$HERE/bin/sparky-stereo-live-gpu-notify" "$D/usr/bin/sparky-stereo-live-gpu-notify"
install -Dm755 "$HERE/share/initramfs/hooks/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/hooks/sparky-stereo-live-gpu"
install -Dm755 "$HERE/share/initramfs/scripts/init-top/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/scripts/init-top/sparky-stereo-live-gpu"
install -Dm755 "$HERE/share/initramfs/scripts/init-bottom/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/scripts/init-bottom/sparky-stereo-live-gpu"
install -Dm644 "$HERE/share/autostart/sparky-stereo-live-gpu.desktop" "$D/etc/xdg/autostart/sparky-stereo-live-gpu.desktop"
install -Dm644 "$HERE/share/plasma-env/sparky-stereo-primary-gpu.sh" "$D/etc/xdg/plasma-workspace/env/sparky-stereo-primary-gpu.sh"
install -Dm755 "$HERE/bin/sparky-stereo-opengl-default" "$D/usr/bin/sparky-stereo-opengl-default"
install -Dm755 "$HERE/bin/sparky-stereo-nvidia-opengl" "$D/usr/bin/sparky-stereo-nvidia-opengl"
install -m644 "$HERE/share/nvidia-opengl-programs" "$D/usr/share/sparky/sparky-stereo-hardware/"
install -Dm644 "$HERE/share/plasma-env/sparky-stereo-opengl.sh" "$D/etc/xdg/plasma-workspace/env/sparky-stereo-opengl.sh"
install -Dm644 "$HERE/share/systemd/sparky-stereo-opengl-default.service" "$D/usr/lib/systemd/system/sparky-stereo-opengl-default.service"
install -Dm644 "$HERE/share/systemd-user/sparky-stereo-opengl.conf" "$D/usr/lib/systemd/user/plasma-kwin_wayland.service.d/sparky-stereo-opengl.conf"
install -Dm644 "$HERE/share/udev/71-sparky-stereo-opengl-default.rules" "$D/usr/lib/udev/rules.d/71-sparky-stereo-opengl-default.rules"
# NVIDIA's services run only with NVIDIA's driver loaded, decided at every boot and when a card is added
for u in nvidia-persistenced nvidia-powerd; do
	install -Dm644 "$HERE/share/systemd/nvidia-units/sparky-stereo-hardware.conf" "$D/usr/lib/systemd/system/$u.service.d/sparky-stereo-hardware.conf"
done
install -Dm644 "$HERE/share/udev/71-sparky-stereo-nvidia-units.rules" "$D/usr/lib/udev/rules.d/71-sparky-stereo-nvidia-units.rules"

sparky-stereo-problems catalog sparky-stereo-hardware "$HERE/problems-lang" "$D/usr/lib/systemd/catalog" \
	--subject LOCAL1=LOCAL2,LOCAL3,LOCAL4 --subject LOCAL9=LOCAL5,LOCAL6,LOCAL7,LOCAL8,LOCAL10,LOCAL11,LOCAL12,LOCAL13,LOCAL14,LOCAL15,LOCAL16 \
	--subject LOCAL17=LOCAL18
