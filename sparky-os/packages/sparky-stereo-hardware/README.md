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
Start Hardware Setup from the menu, or run `sparky-stereo-hardware --auto` as root from the installer/first-boot workflow. Repeat the command when hardware changes. On a machine whose NVIDIA card the edition's driver supports, the plan window offers "Install matched support" (with the edition's NVIDIA driver: its open modules with [HDMI®](https://www.hdmi.org/resource/brand) 3D on Turing and newer, NVIDIA's 580 driver on Maxwell, Pascal and Volta) and "Install matched support, keep nouveau"; in a terminal, `--nvidia edition` (the default) or `--nvidia nouveau`. A run with errors ends with their list and exit status 1. The package enables one boot service, the OpenGL stereo default below, and a live-session notification (since 0.1.8); hardware setup itself runs only when asked.

`--dry-run` prints matched packages and actions without installing, editing configuration, or probing sensors. To reproduce the supplied example inside a container: `sparky-stereo-hardware --auto --dry-run --fixture tests/fixtures/creative-nvidia-laptop`. Fixtures are plain text and require every fact file; `laptop` contains laptop-detect's exit code, 0 for laptop or 1 for desktop. Fixture mode cannot apply changes. Container execution without fixtures is rejected.

Read-only facts, printed as `fact` lines in the plan (since 0.1.2; they need the files `ldso-help`, `dmi-board-vendor`, `dmi-board-name` that the tool collects, and a fixture without them prints none): `cpu-level` (v1 to v4, from the lines of `ld.so --help` marked "supported, searched"; the flags of `/proc/cpuinfo` are checked against the x86-64 level definitions and a disagreement is printed), `x86-64-v3` (yes or no, the question the edition's CPU level asks), `board` (DMI vendor and name), `usb-vendors` (every USB vendor ID present, with the name for the peripheral makers the study lists), `network-pci` and `network-driver` (network PCI IDs and the in-kernel driver that claims each, from `share/network-ids.tsv`). A card that needs firmware names its package (an MT7922 names `firmware-mediatek`; Intel Wi-Fi `firmware-iwlwifi`; Qualcomm Atheros `firmware-atheros`; Realtek `firmware-realtek`), and nothing is installed for it that the hardware list does not already install. For a Broadcom card from the closed-driver list the tool prints a `candidate` line naming Debian's `broadcom-sta-dkms` and saying a licence must be shown before it is installed; nothing installs it yet. Where these values come from is named in the comments of `lib/detect.py` and `share/network-ids.tsv`: CachyOS's chwd and cachyos-repo.sh, Debian's broadcom-sta-dkms README, the kernel's ID tables, the OpenRGB project's documentation and apt's varianttable.

The test is `tests/container-detection.sh` (a debian:testing container, no .deb build): `tests/detection.py` runs the existing cases and the fixtures `gigabyte-corsair-v3`, `razer-mt7922-v3`, `broadcom-4331-v2` and `baseline-cpu` (synthetic: the IDs are real, the machines are not), and `tests/nvidia-branches.py` the NVIDIA fixtures `nvidia-turing-gtx1660s`, `nvidia-pascal-gtx1080`, `nvidia-maxwell-gtx960m-laptop`, `nvidia-kepler-gtx680` and `nvidia-unknown-ffff` (since 0.1.18).

The GUI previews the plan and runs installation visibly in sparky-xterm. GUI labels and the error messages are provided in English, Polish, Brazilian Portuguese, French, German, Japanese, Korean, Simplified Chinese and Traditional Chinese (the language files' LOCAL strings, chosen from `/etc/default/locale`; the error messages are LOCAL29 to LOCAL54, numbered, so the window at the end of a run shows each error in the person's language). Diagnostic logs use English, every ERROR line included, for support, and include command output; automatic mode logs under `/var/log/sparky-stereo-hardware/`.

NVIDIA open support follows NVIDIA's 615.71.09 PCI table, including subsystem restrictions. Unknown cards and mixed supported/unsupported NVIDIA systems keep nouveau, and the plan says why.

NVIDIA's 580 driver for Maxwell, Pascal and Volta cards (since 0.1.18, ORDER 354): NVIDIA's 580 branch is the last that runs them, and the edition builds its kernel modules for the edition's kernels (nvidia-legacy-580xx-kernel-dkms, NVIDIA's DKMS tree unmodified; it builds on Linux 7.3 with no patch). A machine whose every NVIDIA card is in `share/nvidia-legacy-580xx.ids` (the "legacy_580.xx" table of NVIDIA's 615.71.09 README, subsystem restrictions kept; see `share/nvidia-legacy-source.txt`) gets the plan action `nvidia-legacy-580xx`, and the plan shows both drivers, because they give the person different results (Daniel, 2026-10-14: "where two paths appear differ, make sure it's a user option then and do both"):
- NVIDIA's 580 driver, the default ("Install matched support", `--nvidia edition`): the card at its full clocks, hardware video decoding (NVDEC, through nvidia-vaapi-driver) and CUDA 12. NVIDIA's display code is closed in this driver (its KAPI carries only the HDR InfoFrame), so the edition's HDMI® 3D patches do not reach it: no HDMI® 3D modes, a 3D television does not switch itself into 3D, and there is no frame packing. Stereo KWin's outputs that need nothing of the driver work: anaglyph, interleaved, side by side and top and bottom for a screen switched into 3D by hand, and output pairs.
- nouveau ("Install matched support, keep nouveau", `--nvidia nouveau`): the edition's HDMI® 3D modes (the television switches itself, frame packing), but nouveau runs these cards at their boot clocks (its feature matrix: power management TODO on Pascal and Volta, WIP on Maxwell) and has no video decoding for them (TODO on Maxwell, Pascal and Volta), so video is decoded in software.
The default follows the edition's rule that hardware video decoding and the drivers it needs come out of the box (Daniel, 2026-10-23: "user has not to configure, out of the box full experience, including the drivers needed to"); which driver is the default for these cards is Daniel's call.
The window says both, in the person's language, above the plan (LOCAL8), and the plan's `choice` lines say them in English.
The setup installs sparky-stereo-nvidia-legacy-580xx-driver-lock and sparky-stereo-cuda-repo first (the repository package only where it is not installed), in a transaction of their own, then reads the repositories, checks the transaction with apt's simulation and installs nvidia-driver and libnvcuvid1 at the module's own version (580.196.07-1+sparky2+lc1: the edition carries NVIDIA's 580 user space at it), the module and nvidia-vaapi-driver, with `--allow-downgrades`: an image's 615 user space goes back to 580, and the open modules go (they conflict). The CUDA repository package is there for NVIDIA's EGL platform libraries (since 0.1.19): NVIDIA's 580 nvidia-driver-libs depends on libnvidia-egl-xcb1 and libnvidia-egl-xlib1 (>= 1:1.0.1), NVIDIA's epoch, which only NVIDIA's repository has (Debian has 1.0.3-1), as on the 615 path; its 615 lock, which the package depends on, decides nothing while the 580 lock is installed. CUDA 13 does not run on these cards, and the setup installs no CUDA toolkit. It installs no runtime power management (NVIDIA's README: "This feature requires a Turing or newer GPU"). Each failure is an ERROR line (LOCAL55 and LOCAL56 for the module, LOCAL42 to LOCAL45 for the transactions, each with LOCAL58, the nouveau choice that keeps HDMI® 3D), and what the run installed is purged.
The 580 lock's file sorts before the 615 lock's and names the same packages, so while it is installed it decides every NVIDIA driver package; sparky-stereo-cuda-repo depends on the 615 lock, which stays installed. The open modules' path therefore purges the 580 lock and module first, when they are installed (LOCAL57 when that fails).
NVIDIA's 580 user space comes from the edition's repository: NVIDIA publishes it for Debian only in its repository for Debian 12, whose only key (EB693B3035CD5710E231E123A4B469963BF863CC) is bound with a SHA-1 signature that Debian 14's APT refuses (apt 3.3.3 with sqv 1.5.0: "SHA1 is not considered secure since 2026-02-01"). The edition carries NVIDIA's own packages (since 0.1.19; the build tree's nvidia-legacy-580xx-userspace): NVIDIA's files byte for byte, NVIDIA's signature checked with gpgv at build time, at the module's version, which the 580 lock keeps at 1005.

NVIDIA's i386 libraries (since 0.1.19): where dpkg has i386, both NVIDIA paths install nvidia-driver-libs:i386 and libcuda1:i386 at the driver's version, so Steam's, Wine's and 32-bit games' OpenGL, Vulkan and CUDA run on NVIDIA's driver. On the 615 path they come from NVIDIA's CUDA repository at the locked version: apt reads its one flat index for every architecture dpkg has, whatever the source's Architectures option says (measured with apt 3.3.3: Architectures: amd64, i386 or none give the same candidates). On the 580 path they come from the edition's repository. Debian's Steam packages only suggest nvidia-driver-libs, so a machine that gets i386 after the setup needs them brought another way.

NVIDIA's i386 libraries when i386 comes later (0.1.20, 0.1.21): dpkg's post-invoke hook (/etc/dpkg/dpkg.cfg.d/sparky-stereo-hardware) runs `/usr/lib/sparky-stereo-hardware/nvidia-i386 check` after every dpkg run, and where NVIDIA's driver is installed for amd64, dpkg has i386 and the two i386 libraries are missing at the driver's version:
- inside an apt run (apt holds dpkg's frontend lock for its whole run and says so to dpkg with DPKG_FRONTEND_LOCKED), the hook starts sparky-stereo-hardware-nvidia-i386.service without waiting for it, and the run's terminal is told; the unit waits until that run has ended (apt-get with DPkg::Lock::Timeout=-1, which waits as long as the lock is held), asks apt whether it can install them (a simulation, without the locks), then installs them under the edition's engine and keeps a notice for this boot, which the session shows; so the usual `dpkg --add-architecture i386; apt-get update; apt-get install steam-installer` ends with them installed, and the person's own run never waits on the unit;
- after a dpkg run of its own (dpkg --add-architecture i386, dpkg -i), whose hooks run with dpkg's locks already free, nothing is started: a unit would run at once, beside the apt-get update the person runs next, which takes only the lists lock and never waits for it; the engine keeps the problem "NVIDIA's 32-bit libraries are missing" and the terminal is told that the next apt run brings them;
- a failed install (no network, the version gone from the repositories) keeps the problem with apt's output and the Repair, `sparky-stereo-hardware --nvidia-i386` (apt-get update, then both libraries at the driver's version); where no unit can be started (systemd not running, a chroot, policy-rc.d forbidding it, the unit masked), the problem says that;
- the problem clears when the libraries are in. The unit is static: `systemctl mask sparky-stereo-hardware-nvidia-i386.service` switches the automatic install off, and the problem then says so.
Since 0.1.22, Repair says on the terminal that it waits for a running apt or dpkg operation before installing the libraries. Its apt-get install uses `DPkg::Lock::Timeout=-1`, as the automatic unit does. Package-list updates still use apt-get update and report any failure through the engine.

Kepler and older cards name, in the plan, the NVIDIA legacy branch that last ran them (`share/nvidia-legacy-older.tsv`: 470.xx, 390.xx, 367.xx, 340.xx, 304.xx, 173.14.xx, 96.43.xx, 71.86.xx); the edition does not build those branches, and the card keeps nouveau. A machine with NVIDIA cards that need different drivers keeps nouveau, and the plan says what each card needs. Before the NVIDIA transaction, firmware-nvidia-graphics is installed for nouveau, the driver the card runs on until the reboot.

Nothing falls back to something else on its own (since 0.1.16; Daniel, 2026-11-01: "either it works or not and the user must know"). A missing edition module, a module version that names no NVIDIA version, a failed install of the repository package or of the lock, a failed `apt update` or a failed apt preflight stops the NVIDIA setup with an ERROR line that says what failed, why and what to do; the packages the run installed for it are purged, and the setup exits non-zero. A failed actual apt transaction is an error requiring inspection; the tool does not pretend it rolled back partially installed drivers. Existing NVIDIA installations are not removed automatically.

nouveau instead of the edition's driver on a supported card is only the person's choice: the plan window's button "Install matched support, keep nouveau", or `--nvidia nouveau` (the default is `--nvidia edition`). Every other step works the same way: a package that cannot be installed, a power-profiles-daemon action the machine does not offer, a wheel driver without headers for the running kernel or an unexpected failure is an ERROR line, the run ends with the list of them and exit status 1, and when the menu started it the list also opens in a window before the terminal closes.

NVIDIA's CUDA repository comes from the edition's package sparky-stereo-cuda-repo: its source, NVIDIA's key and the edition's pins (CUDA updates, NVIDIA's driver stays at the module's version, NVIDIA's builds of Debian's own tools such as dkms do not replace Debian's; see that package's README). Since 0.1.15 the setup installs it with sparky-stereo-nvidia-driver-lock in a transaction of their own, then reads the repository, so the lock and the pins are in force when apt chooses NVIDIA's user space; before, the setup wrote the source and a pin of every NVIDIA package at 1002 itself, and the lock came only as the module's dependency, in the driver's own transaction. A CUDA repository the person set up already (a source naming NVIDIA's URI outside a comment, such as NVIDIA's own cuda-keyring) is kept as it is and named in the log, and sparky-stereo-cuda-repo still comes with the lock: since its version 20261101.2 it writes no source of its own when another source names NVIDIA's URI (a second source for it with another key file would stop apt), and its pins go by origin, so they apply to the person's source too (since 0.1.16; 0.1.15 added only the lock there). The package recommends sparky-stereo-cuda-repo (since 0.1.16), so an installed system takes the narrowed pin and the edition's dkms with an ordinary upgrade. The install names both nvidia-driver at the module's NVIDIA version (the version of nvidia-kernel-open-dkms-stereo3d without its +stereo3d suffix and Lean Code's +lc mark, read from apt: 615.71.09-2+stereo3d7+lc1 gives 615.71.09-2) and nvidia-kernel-open-dkms-stereo3d, plus libnvcuvid1 at that same NVIDIA version and nvidia-vaapi-driver. libnvcuvid1 pulls the matching libcuda1; nvidia-driver alone does not install either decoding runtime.

On an upgraded system with the old hand-written CUDA pin at 1002, the first upgrade installs sparky-stereo-cuda-repo and replaces that pin.
APT chose that transaction before the replacement, so the edition's dkms becomes the candidate for the second upgrade.
Run `apt update` and `apt full-upgrade` again after the first upgrade finishes.
With sparky-stereo-apt 20261102~sparky9~0, Debian's dkms is blocked by the generated only-ours list; a fresh installation with the packaged pins already in place selects the edition's dkms immediately.

Creative support preserves the four original blobs in `/usr/lib/firmware/updates/` and uses `snd_hda_intel enable_msi=1`. It does not unload active audio. Reboot after driver/firmware changes. Xbox USB matches preinstall xpadneo for later Bluetooth pairing; xpadneo itself handles Bluetooth, not the USB transport. DisplayLink installs evdi-dkms; a working dock also needs its userspace DisplayLink component supplied by the edition.

Purging the setup tool removes its executable and menu files. It deliberately retains hardware packages, logs and generated sensor/audio/APT configuration so removing the UI does not disable installed hardware. Purge the individual firmware/DKMS package to remove its payload. Driver readiness, sensor readings and audio output on real hardware remain separate from container fixture proof.

APT preferences for the GPU vendors' repositories (since 0.1.5):
-------------
Two files in /etc/apt/preferences.d, read by apt whether or not the vendor's repository is configured (a pin for an absent repository does nothing):

sparky-stereo-gpu-nvidia: NVIDIA publishes its container toolkit (libnvidia-container1, libnvidia-container-tools, nvidia-container-toolkit, nvidia-container-toolkit-base) twice, in nvidia.github.io and in the CUDA repository, as different builds of the same versions; with the two repositories at different priorities apt "downgrades" between the copies at every upgrade (NVIDIA/nvidia-container-toolkit#2137). Both origins get 990 for those four packages, so the newer version wins from either and an equal version never flips; release candidates (any version containing ~rc, matched as the regular expression /~rc/, because apt drops a trailing * from a version pattern before glob matching, so *~rc* never matches) get 100. The edition's libnvidia-egl-wayland1 and libnvidia-egl-wayland-dev win over the copies in NVIDIA's CUDA repository (500), whose other packages sparky-stereo-cuda-repo pins. The Multi-Arch: same libraries (libnvidia-container1, libnvidia-egl-wayland1, libnvidia-egl-wayland-dev) are named with :any, because apt matches a plain name only on the native architecture (apt_preferences(5): "By default, only packages of the native architecture are matched. To match binary packages of any architecture, add the :any suffix to the package name.") and every architecture of such a library must have the same version: without it, NVIDIA's i386 egl-wayland 1:1.1.21-1 stayed at the CUDA repository's 1002 and won over ours on machines where NVIDIA's repository is read for i386 too (its own cuda-keyring package sets it up for every architecture), while the amd64 copy was ours (ORDER 318, since 0.1.14). The toolkit's programs are Multi-Arch: no, one architecture at a time, and keep their plain names.

sparky-stereo-gpu-amd: AMD's out-of-tree kernel driver (amdgpu-dkms, amdgpu-dkms-firmware and their former names rock-dkms, rock-dkms-firmware) is never installed, from any source: the edition's kernel carries amdgpu with the HDMI® 3D changes. Every package whose name contains amdgpu (and AMDVLK) from AMD's repositories (Release origin repo.radeon.com) is never installed either: they all depend on amdgpu-core, whose postinst writes /etc/ld.so.conf.d/20-amdgpu.conf and puts /opt/amdgpu/lib ahead of the system's libraries for every program (libdrm, libgbm, libEGL_mesa, libGLX_mesa), and mesa-amdgpu-vulkan-drivers sets VK_LOADER_DRIVERS_DISABLE=radeon_icd.* in /etc/environment.d, which turns off the distribution's Vulkan driver. amdgpu-install and amdgpu-insecure-instinct-udev-rules stay available (500). ROCm is not touched and updates normally: AMD's current ROCm for Debian 13 (stable.repo.amd.com) depends on none of these packages, and in the older repo.radeon.com ROCm only rocdecode and rocjpeg need AMD's graphics Mesa.

Intel is not guarded: i915 has carried HDMI® stereo modes upstream since 2013, and Intel's repositories do not replace the kernel driver.

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

`sparky-stereo-opengl-default --opengl nvidia` (as root) keeps NVIDIA's own OpenGL for every program instead; `--opengl zink` returns to the default. Either applies from the next login. Per program, `gl-stereo-run --nvidia-opengl zink|nvidia` and its settings dialog choose: `nvidia` and 3D off run the program on NVIDIA's own OpenGL. A program that needs NVIDIA's OpenGL itself (CUDA and OpenGL sharing, NVIDIA-only extensions) can be started that way.

Programs that keep NVIDIA's own OpenGL (since 0.1.10): CUDA and OpenGL sharing needs NVIDIA's OpenGL, since under zink CUDA finds no device behind the OpenGL context (`cuGLGetDevices` and `cuGraphicsGLRegisterBuffer` return `CUDA_ERROR_INVALID_GRAPHICS_CONTEXT`; measured on an RTX 3060). With the zink default the session script starts the programs in `/usr/share/sparky/sparky-stereo-hardware/nvidia-opengl-programs` through `sparky-stereo-nvidia-opengl`, which removes the zink variables and starts the program: it copies their menu entries into `$XDG_RUNTIME_DIR/sparky-stereo-opengl/applications` with every `Exec` line starting through the wrapper, ahead of the system's in `XDG_DATA_DIRS`, and writes a script by each program's name, for a terminal or a script, ahead of the system's in `PATH`. The list starts with DaVinci Resolve (`resolve`) and NVIDIA's control panel (`nvidia-settings`). `/etc/sparky-stereo/opengl-programs` (the administrator) and `~/.config/sparky-stereo/opengl-programs` (the person, read last, so the person's choice wins) take one line per program: `NAME nvidia` adds a program, `NAME zink` gives a listed one back to zink. A menu entry the person keeps in `~/.local/share/applications` stays theirs. Changes apply from the next login. Any program can be started this way by hand: `sparky-stereo-nvidia-opengl PROGRAM [ARGUMENT...]`.

The test is `tests/opengl-default.sh` (fixture sysfs trees, menu entries and lists).

HDMI®, HDMI® High-Definition Multimedia Interface and the HDMI® Logo are trademarks or registered trademarks of HDMI Licensing Administrator, Inc.
