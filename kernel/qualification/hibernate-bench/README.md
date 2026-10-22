# hibernate-bench

A small test bench that boots a Linux kernel in QEMU with **UEFI Secure Boot (OVMF)** and a **software TPM 2.0 (swtpm)**, hibernates it to a disk, resumes it, and tries to tamper with the image, the kernel and the TPM in between.

It answers questions such as:

- Does this kernel, booted under Secure Boot, **refuse an unsigned module** and **accept a module signed by an enrolled key**?
- Is **hibernation available** under Secure Boot, and does a full **hibernate and resume cycle** work?
- Is hibernation **refused under `lockdown=integrity` / `lockdown=confidentiality`**, as the kernel documents?
- If a kernel claims to allow hibernation under lockdown by **encrypting the image**: is the image really unreadable on disk, and does resume **refuse** an image with a flipped bit, a different kernel, or a changed PCR?

Everything runs with throw-away keys generated on the first run. There is nothing to enrol on your machine, nothing to sign with a key of yours, and nothing is installed on the host when you use the Docker wrapper.

## What you need

- A kernel to test: an x86-64 `bzImage` built with `CONFIG_EFI_STUB`, virtio-blk, ACPI, a serial console and module support (`kconfig/bench-x86_64.fragment` lists a minimal set; `tools/build-test-kernel.sh` builds such a kernel from any source tree in a few minutes). For the module scenarios the bench also needs that kernel's **build tree** (the `O=` directory, with `scripts/sign-file` and `Module.symvers`), because it compiles and signs a tiny test module against it.
- Docker, or on Debian/Ubuntu: `qemu-system-x86 ovmf swtpm swtpm-tools python3-virt-firmware sbsigntool openssl busybox-static cpio gcc make python3`.
- KVM (`/dev/kvm`) is optional. Without it QEMU uses TCG: slower, but it works.

## Quick start

```sh
# 1. a small test kernel (or use your own)
tools/build-test-kernel.sh ~/src/linux ~/build/bench-kernel

# 2. run the scenarios (first run builds the Docker image, the keys and the initramfs)
./run-in-docker.sh -m ~/src/linux:~/src/linux:ro -m ~/build/bench-kernel:~/build/bench-kernel:ro \
    --kernel ~/build/bench-kernel/arch/x86/boot/bzImage --ksrc ~/build/bench-kernel \
    run policy hibernate lockdown-integrity
```

Without Docker: `./bench --kernel ... --ksrc ... run policy hibernate` after installing the packages above (`./bench doctor` tells what is missing).

### A distribution kernel (modules, your own signature)

A distribution kernel keeps virtio-blk (and most drivers) in modules, so the guest has to load them from its initramfs. Unpack the kernel's image and headers packages and point the bench at them:

```sh
dpkg-deb -x linux-image-REL.deb pkg; dpkg-deb -x linux-headers-REL.deb hdr
./run-in-docker.sh -m $PWD/pkg:$PWD/pkg:ro -m $PWD/hdr:$PWD/hdr:ro \
    --kernel $PWD/pkg/boot/vmlinuz-REL --ksrc $PWD/hdr/usr/src/linux-headers-REL --modules-dir $PWD/pkg run policy hibernate
```

`--modules-dir` takes `lib/modules/REL` or a tree that contains it; `--load-modules "a b"` names the modules to load (default `virtio_blk efivarfs`; dependencies come from `modules.dep`, modules built into the kernel are skipped, compressed modules are decompressed, the module signature survives that). If you signed the kernel yourself, add `--kernel-signed --db-cert your-db-certificate.crt`: the bench enrolls your public certificate next to its own throw-away keys and never needs your private key.

Results are printed as `PASS` / `FAIL` / `INFO` lines per check, followed by a summary. Every run keeps its console logs under `bench-work/runs/<time>-<scenario>/` (`boot1.log`, `boot2.log`, the TPM log, the OVMF variable store). The exit status is 0 when every scenario met its expectation.

The guest uses separate UARTs for kernel diagnostics (`ttyS0`, `bootN.kernel.log`)
and result records (`ttyS1`, `bootN.protocol.log`). It drains the result UART
before poweroff. `bootN.log` concatenates the two retained streams for existing
checks; it is not a chronological merge. This prevents asynchronous kernel
messages from splitting result records, as observed during PREEMPT_RT tests.
The same verdicts and required checks still apply; a drain failure fails completion.

## Scenarios

| scenario | what happens | default expectation |
|---|---|---|
| `policy` | one boot: Secure Boot state from the firmware and from the kernel, lockdown state, keyrings, an unsigned module, a module signed by the enrolled key, a module signed by an unknown key, what `/sys/power` offers | unsigned refused, enrolled loads, unknown refused |
| `tpm` | one boot: is there a TPM 2.0 (`/dev/tpm0`), can PCR 16 and PCR 23 be extended and reset from user space (the application-specific PCRs a hibernation design may use) | both PASS |
| `kexec` | one boot: what `kexec_load(2)` and `kexec_file_load(2)` (signed image, unsigned image, a crash-kernel image) answer, first as the kernel booted, then after `kernel.kexec_load_disabled=1` (set by applying `--guest-sysctl FILE`, or directly) | see below |
| `custom` | one boot that runs your own shell script in the guest (`--guest-script FILE`, tools and libraries from `--guest-dir DIR`); every `bench_check NAME PASS\|FAIL\|INFO detail` line it prints becomes a result | what the script says |
| `hibernate` | boot 1 hibernates, boot 2 resumes; a witness process proves continuity; a random canary in RAM is searched for in the image on disk | the cycle works; the canary result is reported (INFO) |
| `lockdown-integrity`, `lockdown-confidentiality` | the same with `lockdown=...` on the command line | hibernation refused (`--expect-hibernate allow` for a kernel that is meant to allow it: then the image must also be unreadable and the resume must work) |
| `tamper-flip` | hibernate, flip one bit inside the image, try to resume | resume refused (`--expect-tamper accept` to record the opposite) |
| `tamper-kernel-version` | boot 2 uses `--other-kernel`, a build with a different `uname -v` | resume refused |
| `tamper-kernel-code` | boot 2 uses `--other-kernel`, a build with the same `uname -v` but different code | resume refused |
| `tamper-pcr` | extend a TPM PCR (`--pcr N`, default 23) between the boots | resume refused |

A hibernation that dies before the image is complete (a kernel oops or panic while writing: the swap header is not marked) is reported as FAIL with the oops lines, never as "image not readable".

`bench list` prints them. What a **stock kernel** does with the tamper scenarios (measured with this bench, Linux 7.3-rc6 with its small test configuration, Secure Boot on, no encryption): `tamper-pcr` is accepted, because nothing in the image or the kernel depends on the TPM; `tamper-flip` is refused only when the flipped bit breaks the compressed stream (`PM: lzo decompression failed`) and is **accepted** with `--compress none`, because an uncompressed image has no check at all; `tamper-kernel-version` and `tamper-kernel-code` are both **accepted**: on x86 the kernel never compares the kernel it booted with the kernel that wrote the image (`check_image_kernel()` with its `uname` comparison is compiled out when the architecture supplies its own image header, as x86 does; that header holds a magic number, the restore addresses and a digest of the memory map), so a boot kernel with a compatible layout resumes the image. The scenarios exist to show whether a proposed design closes those gaps, so they report FAIL on a stock kernel by design (`--expect-tamper accept` records the opposite expectation).

### What `kexec` measured (Linux 7.3-rc6, distribution-style configuration with `KEXEC_SIG` and IMA's Secure Boot policy, Secure Boot on, no lockdown)

| call | as booted (`kexec_load_disabled=0`) | after `kernel.kexec_load_disabled=1` |
|---|---|---|
| `kexec_load` (no file, so no signature to check) | refused, `EACCES`, by IMA: "impossible to appraise a kernel image without a file descriptor" | refused, `EPERM` |
| `kexec_file_load`, unsigned image | refused, `ENODATA`: "Enforced kernel signature verification failed" | refused, `EPERM` |
| `kexec_file_load`, image signed by a key in `db` | **loads** | refused, `EPERM` |
| `kexec_file_load`, crash (kdump) kernel | refused, `EADDRNOTAVAIL` (this guest reserves no `crashkernel=` memory), not by the toggle | refused, `EPERM` |
| an image staged before the toggle | | stays staged (`/sys/kernel/kexec_loaded`) |

So the toggle does not keep signed `kexec_file_load` working: `kernel/kexec_core.c:kexec_load_permitted()` serves both system calls (and the documentation says so), and under Secure Boot the old call is refused anyway. `--expect-kexec-file allow` states the opposite expectation (a signed image still loads) and fails on this kernel. The option `--guest-sysctl FILE` also tells you which keys of a distribution's sysctl file the kernel does not have or does not accept.

## How it works

- **Firmware.** OVMF with Secure Boot (`OVMF_CODE*.secboot.fd`); the variable store gets a fresh PK, KEK and db from `virt-fw-vars`, Microsoft keys left out. The kernel image is signed with the db key (`sbsign`) and passed with `-kernel`, so the firmware verifies it like any boot loader entry.
- **Control without Secure Boot.** `--no-secure-boot` leaves the variable store in setup mode (no keys): the same scenarios then show what changes when Secure Boot is off (on the kernels tried: "Secure boot disabled", "ima: No architecture policies found", an unsigned module loads), which separates what the Secure Boot policy enforces from what the build configuration enforces.
- **Module trust.** `--module-trust db` (default) enrols the module-signing certificate in db, so the kernel puts it in the platform keyring. `--module-trust mok` writes the variable `MokListRT` that `shim` would have created (the bench boots without shim, so this is a stand-in for the kernel's half of the MOK path, not shim itself). `--module-trust none` leaves trust to the kernel's own keyring (`CONFIG_SYSTEM_TRUSTED_KEYS`).
- **TPM.** `swtpm` (TPM 2.0) on a Unix socket, attached as a CRB device; its state directory survives the power cycle between the boots, its PCRs reset like on a real machine. `tools/tpmcli.c` (static, no library) reads, extends and resets PCRs from the guest.
- **Guest.** A tiny initramfs (static BusyBox plus the scripts in `guest/`) running as PID 1. The two boots of a hibernation scenario use **the same command line, kernel, initramfs and hardware**, because x86 hibernation refuses an image when the memory map differs; per-boot settings (which phase, which tamper) are read from a 512-byte control disk instead.
- **Hibernation.** The guest enables a raw 1 GiB virtio disk as swap, plants a canary and a witness, writes `disk` to `/sys/power/state`, the VM powers off. Boot 2 triggers the resume from the initramfs. If the image is restored, the boot-1 userland continues and reports; if it is refused, boot 2 carries on and reports what the kernel logged.
- **Tampering.** `tools/swsusp.py` finds the image through the swap header (`struct swsusp_header`, `kernel/power/swap.c`) and flips a bit in a data page. A different kernel is booted with `--other-kernel`. A PCR is extended by `tpmcli` before the resume is requested.

## Limits (read these before believing a PASS)

- shim and GRUB are not in the chain. The kernel is started by the firmware directly. The MOK path is emulated as described above.
- swtpm is a software TPM: it proves the kernel's logic, not the behaviour of a particular chip, its bus, or its firmware.
- The canary check shows that a *random 4 KiB block that the guest holds in RAM* is readable on disk. It cannot prove that no other secret is.
- One vCPU by default (`--cpus N` for more) to keep the two boots identical on busy hosts. Boots can time out on a heavily loaded machine; raise `--timeout`.
- ACPI S4 is not used; the bench hibernates with `/sys/power/disk` = `shutdown`.
- The guest userland is BusyBox. A distribution's initramfs, its `resume=` handling and its swap setup are not exercised.

## Layout

```
bench                  the command (bash)
run-in-docker.sh       runs it inside the tool image as your user
Dockerfile             tool image: QEMU, swtpm, OVMF, virt-firmware, sbsign, BusyBox, gcc
guest/                 init, helper library and the phase scripts that run in the guest
module/                the test module
tools/                 tpmcli.c (PCR access), kexectest.c (kexec probes), swsusp.py (image inspection and tampering), mkcpio.py (initramfs without root), modload.py (modules for the initramfs), mokrt.py, build-test-kernel.sh
kconfig/               minimal kernel configuration fragment, and an example with the extra options a TPM-using hibernation patch needs
```

## Licence

GPL-2.0-or-later (SPDX headers in the files), the same family as the Linux kernel the bench is meant to help test. The module in `module/` is GPL-2.0 as it must be.
