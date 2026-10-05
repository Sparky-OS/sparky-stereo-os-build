# What the next kernel build must check

The configuration of `build-deb.sh` changed on 2026-10-05 (`configure.sh`): BTF and sched_ext on, four Realtek drivers on. It was proved on the configuration only, with `tests/config-proof.sh` (a container, a read-only tree, `O=` in a scratch folder, no kernel built). The next real build, and the boot after it, must still show the following.

## The configuration

- `DEBUG_INFO_NONE` is gone. The smallest setting that gives BTF is `DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT` with `DEBUG_INFO_BTF` (`DEBUG_INFO_REDUCED` and `DEBUG_INFO_SPLIT` forbid BTF; `DEBUG_INFO_BTF` needs `BPF_SYSCALL` and pahole 1.22 or newer). It is what Debian's own 7.1.13 kernel carries. `DEBUG_INFO_BTF_MODULES` follows by default, so every module carries a BTF section.
- The build container needs `pahole` (package `dwarves`, 1.32 in forky, already in the script's install line) and `libdw-dev`, `libelf-dev` (already there). `CONFIG_PAHOLE_VERSION=132` in the resulting config.
- `SCHED_CLASS_EXT=y` selects, by default, `EXT_GROUP_SCHED` and `EXT_SUB_SCHED`; BTF also brings `IO_URING_BPF_OPS`, `FUNCTION_TRACE_ARGS`, `PROBE_EVENTS_BTF_ARGS`. `RTW89_8922DE` selects `RTW89_8922D`. The full difference against the previous configuration is 52 lines of `diff`, all of these and the debug-info choice (`tests/config-diff-2026-10-05.txt`, the running kernel's configuration through the old and the new `configure.sh`).

## After the build

- Size of the image package against today's `linux-image-7.3.0-rc1-stereo3d_6_amd64.deb` (94 592 184 bytes) and the headers package against `_6` (9 993 592 bytes). The BTF in vmlinux and in each module makes the image larger; the debug information itself goes to a separate `-dbg` package or is stripped, so check that `bindeb-pkg` did not put DWARF into the image, and that the `cp` line of the script still finds both packages. Record the build time and the size of the build tree too: DWARF for the whole tree is gigabytes where the old build had none.
- `ls /sys/kernel/btf/vmlinux` exists.

## After boot (the development VM first)

- `cat /sys/kernel/sched_ext/state` exists (it is `disabled` until a scx scheduler is loaded; nothing loads one by default).
- `modprobe rtw89_8852au rtw89_8852cu rtw89_8922au rtw89_8922de` loads all four (without the hardware they load and bind to nothing; `modinfo` shows the USB and PCI ID tables).
- `zgrep -E 'SCHED_CLASS_EXT=y|DEBUG_INFO_BTF=y|RTW89_(8852AU|8852CU|8922AU|8922DE)=m' /proc/config.gz` or `/boot/config-<release>` finds all six.
- The drivers need firmware that `firmware-realtek` carries (`rtw89/`); check the file names `modinfo -F firmware rtw89_8922de` lists exist in `/lib/firmware`.
