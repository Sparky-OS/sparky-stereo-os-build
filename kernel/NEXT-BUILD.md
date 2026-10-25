# The kernel build, and what to check after it

`build-deb.sh` builds the edition's kernel from vanilla Linux at a pinned tag, the patch series in `series/` (one file per change, grouped; `series/series.txt` lists them and says why), Debian's own configuration for the nearest kernel (`config/debian-7.2.11-*.config`, provenance in `config/DEBIAN-BASE`) and the edition's fragment (`config/sparky-stereo.config`, one reason above every option). Three flavours: base (generic x86-64), v3 (x86-64-v3) and rt (PREEMPT_RT). A release name is never reused: `-b BUILD` is a new number every time.

```
kernel/build-deb.sh -b 7                 # base
kernel/build-deb.sh -b 7 -f v3           # same sources, ISA level 3
kernel/build-deb.sh -b 7 -f rt           # PREEMPT_RT
kernel/tests/config-proof.sh             # configuration only, all flavours, no kernel built (about 2 minutes)
kernel/tests/package-smoke.sh            # a tiny kernel through the same packaging path (bindeb-pkg, signing, BTF, headers repack, checks): about 15 minutes; run it after any change to build-deb.sh or build-inner.sh
```

Containers get `--cpus 4 --memory 16g`. The packages are unsigned: the kernel image is signed by whoever holds the Secure Boot key (the modules are signed during the build with a key that is deleted afterwards).

Things learned from the first builds (2026-10-08), so that the next one does not repeat them:
- Never put `terse` in `DEB_BUILD_OPTIONS`: `dpkg-buildpackage` then appends `--no-print-directory` to `MAKEFLAGS` after the `--` that separates the variables on make's command line (`LOCALVERSION=...`), and `debian/rules` stops with "No rule to make target '--no-print-directory'". The quiet log comes from `KBUILD_VERBOSE=0`.
- The objects of the build tree carry DWARF (BTF is generated from it). Uncompressed, the tree of one flavour would be about 30 GB; `CONFIG_DEBUG_INFO_COMPRESSED_ZSTD=y` (a fragment option, no effect on the packages) makes it much smaller. A flavour needs roughly the tree size plus 0.5 GB of packages, on a disk with the 35 GB floor of `build-deb.sh`.
- One flavour takes about three to four hours on four CPUs; the three flavours are built one after the other (`-b` the same number for all, so that GRUB's version sort puts v3 above base above rt), each tree deleted once its packages are out.
- `linux-libc-dev` is built by `bindeb-pkg` but not collected: its name is the same for every flavour and build.

## What `build-inner.sh` checks before it succeeds

The final `.config` holds every option of the fragments (`configure.sh` stops otherwise); `RUST`, `DEBUG_INFO_BTF`, `SCHED_CLASS_EXT`, `MODULE_SIG_ALL`, `SCHED_BORE` are on, Binder is a module; the kernel release equals the expected name; no package contains the build signing key; a module in the image package carries the signature marker; the headers package contains `Module.symvers`, the `.config` and a BTF-only `vmlinux` (`objcopy -j .BTF -j .BTF_ids`, as Debian's headers do).

## After the build, on the development VM first

- `uname -r` is the release name; `ls /sys/kernel/btf/vmlinux`; `cat /sys/kernel/sched_ext/state` (it is `disabled` until an scx scheduler is loaded).
- `hibernate-bench` (`$SPARKY_WORKSPACES/kernel-soul/work/hibernate-bench`) with the image and the module signing key of the build: Secure Boot on, unsigned module refused, enrolled-key module loads, `/sys/power/disk` offers hibernation, a full hibernate and resume passes, `lockdown=integrity` refuses it.
- DKMS rebuild of the NVIDIA open modules and xpadneo against the new headers package (for the rt flavour: `IGNORE_PREEMPT_RT_PRESENCE=1`). `CONFIG_CGROUP_DMEM` is on from build 13: Linux 7.3 changed `dmem_cgroup_register_region()`, so NVIDIA's open modules need 615.78.08's conftest, which the edition's nvidia-kmod-open 615.71.09-2+stereo3d6 carries (patch 0012); the headers Break older versions of that package.
- `mount -t binder binder /dev/binderfs` after `modprobe binder_linux`; the four Realtek modules and `vkms` load.

## Build 9 (queued 2026-10-09)

- rt gets the guest virtio-gpu stereo patches (series group 33), as base and v3 already have them.
- EV_BTN (queue item 15): Tomasz Pakuła's "Input: New EV_BTN event" series, so joysticks keep more than 80 buttons, with its SDL and Wine parts in our packages; and `HID_WINWING` on.

## Flavour parity (Daniel, 2026-10-21)

All kernel flavours carry the same accepted edition optimizations and fixes.
The RT option serves time-sensitive audio/video, robotics and other workloads;
it must retain the stereo desktop and virtual-display features of base. Compare
the retained patch identities before building, then qualify each configuration.
Document actual RT incompatibilities (for example this tree's i915 Kconfig
excludes PREEMPT_RT); do not silently omit fixes to make a build pass.

The Lean Code build-9 migration now takes RT from the same accepted common
source tree as base, closing build 8's two-patch virtio-gpu omission. Its native
build, VM and DKMS results remain pending. This parity correction does not mark
the separately queued EV_BTN work or the depth/group-34 work complete.

## Build 10 (2026-10-23, ORDER 212): series group 34 shipped, all three flavours at 7.3.0~rc6-10+lc1

- Group 34 (16 patches, vc4's 0016 included) applied in series order, strictly (`git apply`, no fuzz), on build 9's patched trees: base and rt share one tree, v3 has its own (it carries the ISA patch).
  `qualification/prepare-kernel-source.py FLAVOUR --counter 10 --source-dir DIR --manifest FILE` turns such a tree into the Lean Code source; `qualification/run-kernel-build.py FLAVOUR --counter 10` builds it unsigned in a container (about 1 h 50 min for base on four CPUs, 35 minutes of it the single-threaded source projection); the tree is deleted once the packages are retained.
- The packages are unsigned on purpose. The Secure Boot key signs the image afterwards with `qualification/sign-kernel-image.py`, which keeps the Lean Code manifest, marker and md5sums of the image package true (the image is a "left" row of the manifest with its hash; replacing the file alone fails check-debs).
- Headers now depend on `pahole | dwarves`. In Debian forky `dwarves` is a transitional package that depends on `pahole`, and kbuild's `scripts/gen-btf.sh` calls `pahole` for every module (our headers ship a BTF vmlinux and `CONFIG_DEBUG_INFO_BTF_MODULES=y`), so a DKMS build without pahole stops with "pahole: not found" (reproduced, `Error 127`). Depending on the real package keeps that true when the transitional one goes.
- ORDER 139 (DKMS never built for our kernel on the A10) was already fixed by the headers package's postinst (it runs `header_postinst.d`, so image-then-headers and headers-then-image both build); build 10 re-proves it in a clean forky container, both orders, with NVIDIA open, xpadneo, acpi-call, v4l2loopback and vhba, for all three flavours.
- `CONFIG_KUNIT` is off in the shipped kernels, so group 34's KUnit suites cannot run in them. They run in a KUnit kernel built from the same source (`tools/testing/kunit/kunit.py run --arch=x86_64`, QEMU), and vc4's on ARM64. The shipped kernels have VKMS without the configfs series, so the vkms-stereo bench uses a test kernel from the same source plus Louis Chauvet's configfs series and the bench's patches.
- Docker from a lane: the per-lane socat proxy cut attached `docker run` output after the first chunk (the build kept running); use `docker logs` or the unproxied socket for builds.
- Not covered by the unsigned VM run: the matrix with the edition-signed image (`qualification/qualify-kernel-boot.py`, with the 9 hardcoded in it now generalised only in the unsigned script), IGT's kms_3d and the kwin phase of the bench, and any physical output.

## Build 11 (2026-10-23, ORDER 222): Debian parity in the kernel packages, all three flavours at 7.3.0~rc6-11+lc1

Same kernel source as build 10 (the orig tarballs differ only in SOURCE.edition.json); what changed is the packaging, the Debian configuration base and one new package.
- **Image package as Debian's linux-image-7.2.11+deb14-amd64** (`lean/prepare.py`, `lean/maint/`, `lean/stage.sh`): Pre-Depends `linux-base (>= 4.17~)`; Depends `kmod, dracut | initramfs-tools (>= 0.120+deb8u2) | linux-initramfs-tool`; Recommends apparmor; Suggests debian-kernel-handbook, firmware-linux-free, grub-pc | grub-efi-amd64 | extlinux; Breaks fwupdate, initramfs-tools, wireless-regdb below Debian's bounds; maintainer scripts that call linux-update-symlinks (`/vmlinuz`, `/vmlinuz.old`, `/initrd.img`, `/initrd.img.old`), linux-check-removal and linux-run-hooks. dracut first is Debian's order: a machine with no initramfs generator gets dracut from this package, where the edition (initramfs-tools installed) changes nothing.
- **Headers**: Depends `gcc-N-for-host | gcc` with N read from CONFIG_CC_VERSION_TEXT in `stage.sh` (substvar `kernel:Compiler`), linux-base, Debian's `linux-run-hooks headers postinst`; added `scripts/kconfig/conf`, `certs/extract-cert`, `arch/x86/tools/relocs` and `/lib/modules/V/source`. Not done: Debian's `.kernelvariables` (CC = gcc-16) needs a Makefile patch, so DKMS still calls plain `gcc`; the Depends only guarantees that the kernel's compiler is installed.
- **linux-libc-dev from our tree** (`lean/libc-dev.py`, base flavour only): arch all, Multi-Arch: foreign, Debian's layout (`/usr/lib/linux/uapi/ARCH/asm` for 14 kernel architectures, `/usr/include/TRIPLET/asm` links for 22 triplets, the shared headers once) made with the kernel's own `headers_install`; version 7.3.0~rc6-11+lc1 is above Debian's 7.2.11-1 and 7.3-1. libdrm-dev ships its own copies of drm.h and drm_mode.h in `/usr/include/libdrm`: a program that includes those sees libdrm's sync, only `<drm/drm_mode.h>` comes from this package.
- **Config base 7.2.9 to 7.2.11** (`config/DEBIAN-BASE`): three real changes in every flavour, SENSORS_ARCTIC_FAN_CONTROLLER=m (also pinned in the fragment), CRYPTO_SHA512 m to y, the new IMA_DEFAULT_HASH_SHA512 line (not set); HZ_1000, ZRAM zstd and DWARF zstd compression stay.
- Tests: `tests/maint-scripts-proof.sh`, `tests/libc-dev-proof.sh`, `tests/maint-proof/dkms-inner.sh`. The older `lean/check-install-hooks.py` covers the run-parts scripts of builds 9 and 10 only.
- Disk: another lane's scratch on `/` swung free space by 20 GB within minutes and stopped the first base attempt at the 12 GB floor; the second attempt (flat 2 h 30 min, v3 1 h 51, rt 1 h 27) ran through.

## Build 12 (2026-10-24, ORDER 246): series group 35, the kernel below 4 GiB for 32-bit EFI firmware, all three flavours at 7.3.0~rc6-12+lc1

Build 11's accepted source plus one patch (group 35, `x86/kaslr: Keep the kernel below 4 GiB for 32-bit EFI firmware`); the packaging recipe is build 11's.
- **The cause (queue item 171):** a 64-bit kernel on 32-bit UEFI (EFI mixed mode) returns from every firmware call through `__efi64_thunk_ret_tramp` at a 32-bit address. GRUB's `linux` command on i386-efi enters through the boot protocol, so the decompressor's physical KASLR chose the address, anywhere in EFI conventional memory; above 4 GiB the return address was truncated and SetVirtualAddressMap() returned into RAM mapped non-executable. In the 32-bit OVMF rig (QEMU, 4 GiB, GRUB 2.14 i386-efi) build 11 faulted in 24 of 50 boots and master in 33 of 50, every one with the trampoline above 4 GiB; nokaslr passed 25 of 25. The EFI stub (QEMU -kernel through the 32-bit handover entry) already keeps itself below 4 GiB (`EFI_ALLOC_LIMIT`). The trampoline's own page is mapped executable: the NX page in the oops is the truncated address.
- **The fix:** `choose_random_location()` limits `mem_limit` to 4 GiB when the EFI loader signature is EL32 and `CONFIG_EFI_MIXED` is set. Written on upstream master (5b0764a53235); kaslr.c is the same file in our tree. Upstream draft for the x86 and EFI maintainers in the lane's handoff, not sent.
- **Sources:** prepared with `prepare-kernel-source.py FLAVOUR --counter 12 --source-dir DIR --manifest FILE` from build 11's orig trees plus the patch; their git trees are 2143ebbd2148 (base, rt) and 3d9e70b6a7c8 (v3), checked by hashing the prepared trees; build 11's hash to 838787cbb13a and 55c7295afe42 as their manifests say. All three record packaging commit 6e7cfbb.
- **sparky-stereo-boot 0.1.2** drops nokaslr on 32-bit UEFI once every kernel in /boot is from build 12 on (31-sparky-stereo-ia32.cfg; `SPARKY_STEREO_IA32_NOKASLR=auto|yes|no`); Debian's kernel and older builds keep it on, because GRUB gives every kernel the same command line.
- **Proof, unsigned packages:** in the 32-bit OVMF rig through GRUB 2.14 i386-efi, 100 of 100 KASLR boots pass for each flavour (base 95, v3 95, rt 96 different physical addresses, all below 4 GiB). 64-bit OVMF (GRUB x86_64-efi and the EFI stub) and SeaBIOS are unchanged: every boot passes, about half of them above 4 GiB as before. On an installed forky system booted on 32-bit OVMF, update-grub with sparky-stereo-boot 0.1.2 writes no nokaslr for build 12 alone (30 of 30 KASLR boots of its menu pass), and nokaslr in every entry while build 11 is installed beside it; with build 11 and the option set to no, 15 of 30 boots fault, the negative control. The rig is `kernel/tests/efi-mixed/`.
- **Qualification:** `qualify-kernel-unsigned.py` passes for base, v3 and rt (v3's first run lost the resume boot of settings-hibernate in the firmware, before the kernel started, under a load average above 20; the second run passed every check). DKMS as in build 11: NVIDIA open 615.71.09, xpadneo, acpi-call, v4l2loopback, vhba and xone, 18 signed modules per kernel, both install orders, all three flavours. The packages' file lists, control fields and .config equal build 11's in every flavour. Metas 7.3.0~rc6+stereo3d12+lc1 (source 20261024.1) built with `KERNEL_META_VERSION_SUFFIX=+lc1`.

