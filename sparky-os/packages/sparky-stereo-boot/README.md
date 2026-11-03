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

This computer's DKMS key follows the same design.
DKMS signs the modules it builds here (NVIDIA's open modules among them) with this computer's own key, which it makes the first time it signs (/var/lib/dkms/mok.pub, or mok_certificate in /etc/dkms/framework.conf); the installed system's first boot signs the modules its image carries unsigned (dkms's dkms-sign-unsigned.service).
Secure Boot loads them only once that key is in the MOK list too, and no package enrolls it (Debian #1076269).
So its certificate is kept next to every shim as dkms-this-computer.der (removed there when the computer has no DKMS key), by the same steps that keep the edition's, and when DKMS makes or changes the key (sparky-stereo-boot-dkms-key.path, which also checks the enrolment again when depmod writes the running kernel's modules.dep after DKMS installed modules it signed).
GRUB's menu has "Secure Boot: enroll this computer's DKMS key", with the steps in the nine languages, as soon as the certificate is on the partition: GRUB looks for it there when it reads the menu.
Under Secure Boot, a DKMS key that is not enrolled while modules signed with it are installed for the running kernel is said at every boot and kept, naming that entry, until it is enrolled (sparky-stereo-boot-secureboot.service).

Options: /etc/default/sparky-stereo-boot (then: sudo sparky-stereo-boot reapply).
Status: sparky-stereo-boot status

Nothing fails silently.
When a step of the boot's upkeep cannot do what it is for, it says what failed, why and what to do, in the system's language (and in English beside it, for support), and keeps that, with the command, its exit status and the end of its output, in /var/lib/sparky-stereo-problems (the edition's one engine, sparky-stereo-problems) until the step succeeds again.
- sparky-stereo-boot status lists the kept problems; each is shown as a notification at login and whenever a new one is kept (sparky-stereo-boot-problems.path and .service in the person's session).
- sudo sparky-stereo-boot repair runs again what each problem names and clears what succeeds; sudo sparky-stereo-boot dismiss STEP hides one by the person's choice (it comes back if the step fails again).
- Package installation: a failed update-grub fails the package, as grub2's own postinst does (Debian Policy 6.4), so dpkg leaves it half-configured until sudo dpkg --configure -a succeeds. The other steps are said and kept and the package configures, as Debian's own service starts and shim-signed's grub-install do: systemd's reload and the units' start (a unit the system masked is said as its choice), and the certificate on the EFI system partition, which this boot does not need.
- Kernel hooks: a certificate that cannot be placed, or a cleanup that cannot be queued, is said and kept; the kernel still installs, since a failing hook would keep zz-update-grub (run-parts --exit-on-error) from writing its GRUB entry.
- The EFI system partition: named in /etc/fstab but not mounted, the certificate missing from the package, or a copy that fails, is a problem; a machine with no EFI system partition (BIOS) has nothing to place, and a partition without shim is said. This computer's DKMS certificate that cannot be read or written is a problem of its own, and so is, under Secure Boot, a DKMS key that is not enrolled while modules signed with it are installed.
- Removal: a failed grub-editenv, rm or update-initramfs, and on purge a failed update-grub, fails the removal (the package stays half-installed and the removal can run again, Debian Policy 6.7); the messages are in the system's language, written into the postrm.
- Kernel cleanup: apt's simulation naming more than the plan, a failed purge, a boot image or GRUB menu not written again afterwards, or an unexpected error, makes sparky-stereo-kernel-keep.service fail and is kept; the boot files left incomplete are repaired before restarting.
- The 3D splash's hand-over: a failed deactivate, hand-over service, plymouth quit, a login screen that does not start, or no picture before the limit, quits the splash so the login screen can start, keeps the reason and makes the unit fail; a splash that cannot be quit is a problem of its own.
- GRUB: update-grub's output names the resolution GRUB is given and the ones it takes when the firmware does not offer it; no connected screen with an EDID, and a menu font that cannot be made, are kept; /var/lib/sparky-stereo-boot/grub-display records what GRUB was given, and at boot sparky-stereo-boot-check.service compares it with the resolution the kernel received from GRUB, keeping the difference with the choice of SPARKY_STEREO_GRUB=auto.

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
