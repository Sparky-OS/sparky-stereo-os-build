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
- DKMS rebuild of the NVIDIA open modules and xpadneo against the new headers package (for the rt flavour: `IGNORE_PREEMPT_RT_PRESENCE=1`). `CONFIG_CGROUP_DMEM` stays off (Debian's value): Linux 7.3 changed `dmem_cgroup_register_region()` and NVIDIA's open modules 615.71.09 do not compile against the new signature; switch it on only when NVIDIA's release handles it (the kernel-soul lane keeps a compat patch, `work/nvidia-dmem/`).
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
