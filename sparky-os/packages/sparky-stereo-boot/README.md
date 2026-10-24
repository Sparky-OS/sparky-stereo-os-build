sparky-stereo-boot

The boot follows the main screen as the person set it in the display settings: GRUB at its resolution, the boot splash and the login screen in its 3D mode or stereo layout.

Copyright (C) 2026 Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

-------------

How it works:

Stereo KWin keeps each person's display settings in ~/.config/kwinoutputconfig.json.
When the file changes, the session sends it to a socket the system runs, and the system writes what the boot reads:
- GRUB: the main screen's resolution (the 2D base of a 3D mode), kept through the kernel with gfxpayload=keep (/etc/default/grub.d/30-sparky-stereo-boot.cfg, at update-grub, which runs only when the resolution changes);
- the kernel line, from GRUB's environment block: plymouth.stereo= for the boot splash, and video= when the base mode is not the screen's preferred one;
- the login screen: the settings copied to Plasma Login Manager's and SDDM's accounts;
- /var/lib/sparky-stereo-boot/main-output.json, the record.
A stereo boot splash hands the screen to the login screen's KWin with no new mode set: plymouth-quit.service deactivates it, KWin takes the same 3D mode, and the splash quits after KWin's first frame.
On an NVIDIA screen the splash needs NVIDIA's display driver in the boot image: an initramfs hook adds nvidia-drm (with nvidia-modeset, nvidia and their firmware) when the machine has an NVIDIA display device and in a live system, and modeset and fbdev are on (/usr/lib/modprobe.d/sparky-stereo-nvidia-kms.conf). SPARKY_STEREO_NVIDIA_EARLY=yes or no overrides it (then: sudo update-initramfs -u).

On 32-bit UEFI (EFI mixed mode) the firmware returns from every firmware call to a 32-bit address in the kernel image, so the kernel must stay below 4 GiB. The edition's kernels from build 12 on do that themselves and keep KASLR; while any kernel in /boot lacks the fix (Debian's, or an older build), the kernel line gets nokaslr, because GRUB gives every kernel the same line (/etc/default/grub.d/31-sparky-stereo-ia32.cfg; SPARKY_STEREO_IA32_NOKASLR=auto, yes or no).

Options: /etc/default/sparky-stereo-boot (then: sudo sparky-stereo-boot reapply).
Status: sparky-stereo-boot status

-------------

Dependencies:
- python3
- grub-common
- systemd
- plymouth (>= 26.134.222-1+stereo3d1), recommended, for the boot splash in 3D
