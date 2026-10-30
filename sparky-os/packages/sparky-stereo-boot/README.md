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

Secure Boot: the edition's kernels are signed with the Sparky Stereo OS key, which shim accepts once it is in the firmware's MOK list.
A new or reset motherboard, or Secure Boot turned on after the installation, leaves the list without it, and GRUB refuses the kernel ("bad shim loader signature").
So the package keeps the edition's public certificate (sparky-stereo-secureboot-2026.der) next to every shim on the EFI system partition, and GRUB's menu has "Secure Boot: enroll the Sparky Stereo OS key" (/etc/grub.d/35_sparky_stereo_secureboot).
The entry shows the steps in the nine required languages and starts MokManager: Enroll key from disk, the disk, EFI, the system's folder, the certificate, Continue, Yes, Reboot; no password is asked.
Under Secure Boot the menu first asks shim about the newest kernel; when shim refuses it, the entry is the menu's default, so the timeout starts it and the person sees it selected.

Options: /etc/default/sparky-stereo-boot (then: sudo sparky-stereo-boot reapply).
Status: sparky-stereo-boot status

-------------

Dependencies:
- python3
- grub-common
- systemd
- plymouth (>= 26.134.222-1+stereo3d1), recommended, for the boot splash in 3D

Old kernels: after a new kernel has installed successfully (its image, its boot image and its GRUB entry written), each kernel flavour keeps two kernels, the running one and the newest, or the one before the newest when the newest is running.
The others go: their packages only (image, binary, modules, headers, the per-release base package, their -dbg and -lc-hr companions, and the kbuild and headers-common packages that nothing else needs), purged after apt's simulation shows exactly that set, then their module folders that no package owns and their DKMS records.
A general autoremove never runs.
The kernel hook /etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep only records the install, because apt and dpkg hold their lock while it runs; sparky-stereo-kernel-keep.service waits until they are done, does the work and writes one line per removed kernel to the journal (journalctl -u sparky-stereo-kernel-keep).
Nothing happens in a live session, a chroot or a container.
To see the plan: sudo /usr/lib/sparky-stereo-boot/kernel-keep.py --dry-run

Boot images: every update-initramfs -u writes the boot image of every installed kernel, not only the newest's (update_initramfs=all in /etc/initramfs-tools/update-initramfs.conf.sparky-stereo; initramfs-tools' own file is kept as update-initramfs.conf.debian and comes back when the package is removed).
So a boot splash, firmware or module change reaches the older kernel too, and after every kernel removal every kept kernel's boot image and GRUB's menu are written again.
