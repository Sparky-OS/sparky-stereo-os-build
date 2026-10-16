sparky-stereo-hardware
Detect and configure matched hardware for Sparky Stereo OS.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
apt
bash
ca-certificates
coreutils
curl
grep
isenkram-cli
kmod
laptop-detect
libnotify-bin
lm-sensors
nvidia-detect
pciutils
power-profiles-daemon >= 0.30
python3
sed
sparky-remsu
sparky-xterm
udev
usbutils
util-linux
yad

Build:
-------------
OUT=/path/to/workspace/out ./build.sh (inside debian:testing)

Rig drivers:
-------------
Flight and racing access is selected from exact USB pairs in
share/rig-devices.json, with a source for every pair. Stable T300/T248 and
Fanatec models select their DKMS package and the running kernel's exact headers.
Experimental models, an unidentified Thrustmaster initialization device and
the optional Logitech replacement remain candidates. Select one explicitly
with --rig-driver PACKAGE; the helper rejects a package without a detected match.
Use --dry-run first to inspect the plan. The setup does not load a wheel driver
into a running kernel. Reconnect or reboot after installation.

Install:
-------------
su
./install.sh

Uninstall:
-------------
su
./install.sh uninstall

Use:
-------------
Start Hardware Setup from the menu, or run `sparky-stereo-hardware --auto` as root from the installer/first-boot workflow. Repeat the command when hardware changes. The package enables one boot service, the OpenGL stereo default below, and a live-session notification (since 0.1.8); hardware setup itself runs only when asked.

`--dry-run` prints matched packages and actions without installing, editing configuration, or probing sensors. To reproduce the supplied example inside a container: `sparky-stereo-hardware --auto --dry-run --fixture tests/fixtures/creative-nvidia-laptop`. Fixtures are plain text and require every fact file; `laptop` contains laptop-detect's exit code, 0 for laptop or 1 for desktop. Fixture mode cannot apply changes. Container execution without fixtures is rejected.

Read-only facts, printed as `fact` lines in the plan (since 0.1.2; they need the files `ldso-help`, `dmi-board-vendor`, `dmi-board-name` that the tool collects, and a fixture without them prints none): `cpu-level` (v1 to v4, from the lines of `ld.so --help` marked "supported, searched"; the flags of `/proc/cpuinfo` are checked against the x86-64 level definitions and a disagreement is printed), `x86-64-v3` (yes or no, the question the edition's CPU level asks), `board` (DMI vendor and name), `usb-vendors` (every USB vendor ID present, with the name for the peripheral makers the study lists), `network-pci` and `network-driver` (network PCI IDs and the in-kernel driver that claims each, from `share/network-ids.tsv`). A card that needs firmware names its package (an MT7922 names `firmware-mediatek`; Intel Wi-Fi `firmware-iwlwifi`; Qualcomm Atheros `firmware-atheros`; Realtek `firmware-realtek`), and nothing is installed for it that the hardware list does not already install. For a Broadcom card from the closed-driver list the tool prints a `candidate` line naming Debian's `broadcom-sta-dkms` and saying a licence must be shown before it is installed; nothing installs it yet. Where these values come from is named in the comments of `lib/detect.py` and `share/network-ids.tsv`: CachyOS's chwd and cachyos-repo.sh, Debian's broadcom-sta-dkms README, the kernel's ID tables, the OpenRGB project's documentation and apt's varianttable.

The test is `tests/container-detection.sh` (a debian:testing container, no .deb build): `tests/detection.py` runs the existing cases and the fixtures `gigabyte-corsair-v3`, `razer-mt7922-v3`, `broadcom-4331-v2` and `baseline-cpu` (synthetic: the IDs are real, the machines are not).

The GUI previews the plan and runs installation visibly in sparky-xterm. GUI labels are provided in English, Polish and Brazilian Portuguese. Diagnostic logs use English and include command output; automatic mode logs under `/var/log/sparky-stereo-hardware/`.

NVIDIA open support follows NVIDIA's 615.71.09 PCI table, including subsystem restrictions. Unknown cards and mixed supported/unsupported NVIDIA systems keep nouveau. Before the optional CUDA transaction, firmware-nvidia-graphics is installed for nouveau. A missing edition module, unavailable key, checksum mismatch or failed apt preflight leaves the previous repository policy in place. A failed actual apt transaction is an error requiring inspection; the tool does not pretend it rolled back partially installed drivers. Existing NVIDIA installations are not removed automatically.

The CUDA keyring archive is pinned by SHA-256 and only its public key is extracted. The repository has Signed-By and priority 1002. The install names both nvidia-driver at the module's NVIDIA version (the version of nvidia-kernel-open-dkms-stereo3d without its +stereo3d suffix, read from apt) and nvidia-kernel-open-dkms-stereo3d. A changed upstream archive requires reviewing its key and updating the checksum in a new package release.

Creative support preserves the four original blobs in `/usr/lib/firmware/updates/` and uses `snd_hda_intel enable_msi=1`. It does not unload active audio. Reboot after driver/firmware changes. Xbox USB matches preinstall xpadneo for later Bluetooth pairing; xpadneo itself handles Bluetooth, not the USB transport. DisplayLink installs evdi-dkms; a working dock also needs its userspace DisplayLink component supplied by the edition.

Purging the setup tool removes its executable and menu files. It deliberately retains hardware packages, logs and generated sensor/audio/APT configuration so removing the UI does not disable installed hardware. Purge the individual firmware/DKMS package to remove its payload. Driver readiness, sensor readings and audio output on real hardware remain separate from container fixture proof.

APT preferences for the GPU vendors' repositories (since 0.1.5):
-------------
Two files in /etc/apt/preferences.d, read by apt whether or not the vendor's repository is configured (a pin for an absent repository does nothing):

sparky-stereo-gpu-nvidia: NVIDIA publishes its container toolkit (libnvidia-container1, libnvidia-container-tools, nvidia-container-toolkit, nvidia-container-toolkit-base) twice, in nvidia.github.io and in the CUDA repository, as different builds of the same versions; with the two repositories at different priorities apt "downgrades" between the copies at every upgrade (NVIDIA/nvidia-container-toolkit#2137). Both origins get 990 for those four packages, so the newer version wins from either and an equal version never flips; release candidates (any version containing ~rc, matched as the regular expression /~rc/, because apt drops a trailing * from a version pattern before glob matching, so *~rc* never matches) get 100. The edition's libnvidia-egl-wayland1 and libnvidia-egl-wayland-dev win over the copies in NVIDIA's CUDA repository (500), which the NVIDIA setup above adds at 1002.

sparky-stereo-gpu-amd: AMD's out-of-tree kernel driver (amdgpu-dkms, amdgpu-dkms-firmware and their former names rock-dkms, rock-dkms-firmware) is never installed, from any source: the edition's kernel carries amdgpu with the HDMI 3D changes. Every package whose name contains amdgpu (and AMDVLK) from AMD's repositories (Release origin repo.radeon.com) is never installed either: they all depend on amdgpu-core, whose postinst writes /etc/ld.so.conf.d/20-amdgpu.conf and puts /opt/amdgpu/lib ahead of the system's libraries for every program (libdrm, libgbm, libEGL_mesa, libGLX_mesa), and mesa-amdgpu-vulkan-drivers sets VK_LOADER_DRIVERS_DISABLE=radeon_icd.* in /etc/environment.d, which turns off the distribution's Vulkan driver. amdgpu-install and amdgpu-insecure-instinct-udev-rules stay available (500). ROCm is not touched and updates normally: AMD's current ROCm for Debian 13 (stable.repo.amd.com) depends on none of these packages, and in the older repo.radeon.com ROCm only rocdecode and rocjpeg need AMD's graphics Mesa.

Intel is not guarded: i915 has carried HDMI stereo modes upstream since 2013, and Intel's repositories do not replace the kernel driver.

The NVIDIA driver itself is locked by sparky-stereo-nvidia-driver-lock, built with the edition's NVIDIA module (nvidia-kernel-open-dkms-stereo3d) from the same version, see its README.Debian. The tool reads the module's version from apt, so the driver version follows the module with no edit in lib/actions.sh. What does not follow by itself is share/nvidia-open.ids, the PCI table of the version it was taken from (see its source file): update it when the module moves.

Tests:
-------------
In a disposable Debian testing container, install the built packages and run `python3 tests/detection.py` and `bash tests/actions.sh`. The latter uses command doubles and a fake root for module loading and NVIDIA transactions. The test never loads a real module. See REPORT.md for the full build/install/use/purge transcript and limitations.

Since 0.1.3, a successfully installed NVIDIA driver on a matched laptop adds
NVreg_DynamicPowerManagement=0x02 and GPU bind/unbind rules for runtime PM.
They apply at the next bind or reboot. Desktops, older/unknown GPUs and failed
driver transactions receive no new runtime-PM files. Hardware and ACPI must
support RTD3; configuring it is not a measurement that the GPU powers down.
The option and rules follow NVIDIA's 615.71.09 runtime-D3 documentation:
https://download.nvidia.com/XFree86/Linux-x86_64/615.71.09/README/dynamicpowermanagement.html

Matched Radeon systems with AMD CPUs opt into PPD's amdgpu_dpm action; laptops
also opt into amdgpu_panel_power. Setup queries and verifies the daemon's
exposed actions using powerprofilesctl. PPD owns the clock and panel changes,
including changes from a user's profile choice. Missing actions are reported
as unsupported, and no second controller writes GPU sysfs. PPD 0.30 currently
probes these actions by CPU vendor, so Radeon on Intel is not covered. Sources:
https://sources.debian.org/src/power-profiles-daemon/0.30-2/src/ppd-action-amdgpu-dpm.c/
https://sources.debian.org/src/power-profiles-daemon/0.30-2/src/ppd-action-amdgpu-panel-power.c/

OpenGL stereo default (since 0.1.9):
-------------
NVIDIA's OpenGL gives a window no second view (its window surfaces take one colour buffer), so a program that draws its own two views gets none on NVIDIA's own OpenGL. Mesa's OpenGL running on NVIDIA's Vulkan driver (zink) has them. `sparky-stereo-opengl-default` finds the card the desktop runs on (the card KWin renders on: the boot VGA card when it can render, else the first card with a screen and a render node, the order of `sparky-stereo-primary-gpu.sh`) and writes `/etc/sparky-stereo/opengl-stereo.conf`: `desktop=nvidia` when NVIDIA's driver runs it, `mesa` for AMD, Intel, nouveau or a hybrid laptop whose desktop runs on the integrated card, `none` without a card that renders, and `opengl=zink` (the default) or `nvidia`, the person's choice, kept across rewrites. It runs at install (postinst; in the installer that is the machine being installed), at every boot (`sparky-stereo-opengl-default.service`, before the display manager) and when udev sees a card added or removed or a display device bound to or unbound from its driver.

At login, `/etc/xdg/plasma-workspace/env/sparky-stereo-opengl.sh` reads it. With `desktop=nvidia` and `opengl=zink` it exports, for the session's programs (menu, panel, terminal alike): Mesa's EGL vendor first and NVIDIA's second (`__EGL_VENDOR_LIBRARY_FILENAMES`; NVIDIA's Vulkan driver does not start without its own EGL vendor), `__GLX_VENDOR_LIBRARY_NAME=mesa`, `MESA_LOADER_DRIVER_OVERRIDE=zink` and `LIBGL_KOPPER_DISABLE=1` (Mesa's own presentation path carries the two views; zink's Vulkan swapchain path, kopper, has none yet). A systemd drop-in for `plasma-kwin_wayland.service` removes these variables from KWin, so KWin and its Xwayland keep NVIDIA's driver. Nothing is exported when the session starts KWin without systemd (`systemdBoot=false` in startkderc) or when the person set an EGL vendor list or a Mesa driver of their own. Vulkan programs are not affected. It also exports `GL_STEREO_NVIDIA_OPENGL`, the system choice, which gl-stereo-run uses as its default.

`sparky-stereo-opengl-default --opengl nvidia` (as root) keeps NVIDIA's own OpenGL for every program instead; `--opengl zink` returns to the default. Either applies from the next login. Per program, `gl-stereo-run --nvidia-opengl zink|nvidia` and its settings dialog choose: `nvidia` and 3D off run the program on NVIDIA's own OpenGL. A program that needs NVIDIA's OpenGL itself (CUDA and OpenGL sharing, NVIDIA-only extensions) can be started that way. The test is `tests/opengl-default.sh` (fixture sysfs trees).
