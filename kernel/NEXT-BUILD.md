# The kernel build, and what to check after it

`build-deb.sh` builds the edition's kernel from vanilla Linux at a pinned tag, the patch series in `series/` (one file per change, grouped; `series/series.txt` lists them and says why), Debian's own configuration for the nearest kernel (`config/debian-7.2.9-*.config`, provenance in `config/DEBIAN-BASE`) and the edition's fragment (`config/sparky-stereo.config`, one reason above every option). Three flavours: base (generic x86-64), v3 (x86-64-v3) and rt (PREEMPT_RT). A release name is never reused: `-b BUILD` is a new number every time.

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
- `hibernate-bench` (`/K3D/temp/partners/queue/kernel-soul/work/hibernate-bench`) with the image and the module signing key of the build: Secure Boot on, unsigned module refused, enrolled-key module loads, `/sys/power/disk` offers hibernation, a full hibernate and resume passes, `lockdown=integrity` refuses it.
- DKMS rebuild of the NVIDIA open modules and xpadneo against the new headers package (for the rt flavour: `IGNORE_PREEMPT_RT_PRESENCE=1`). `CONFIG_CGROUP_DMEM` stays off (Debian's value): Linux 7.3 changed `dmem_cgroup_register_region()` and NVIDIA's open modules 615.71.09 do not compile against the new signature; switch it on only when NVIDIA's release handles it (the kernel-soul lane keeps a compat patch, `work/nvidia-dmem/`).
- `mount -t binder binder /dev/binderfs` after `modprobe binder_linux`; the four Realtek modules and `vkms` load.
