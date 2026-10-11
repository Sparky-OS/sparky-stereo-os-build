# Hibernate and resume with the Cushion Swap File: guest test

`guest-hibernate.py` is one self-contained Python 3 script for a disposable
VM (Debian's own commands only). It refuses a container or a machine that
systemd does not identify as a VM. Run it as root.

## Where the image goes

Daniel, 2026-10-10: Hibernate is configured by the installer's
`/etc/initramfs-tools/conf.d/resume` ("pointing to the file"):
`RESUME=UUID=...` names the device, `RESUME_OFFSET=` a swap file's first
page on it, `RESUME=none` no hibernation. Without a `RESUME=` line there,
`resume=` and `resume_offset=` on the kernel command line are the second
source. The probe finds the area that way on its own, then checks that
sparky-stereo-cushion-swap's `cushion-swap --resume-target` names the same.

initramfs-tools 0.151 reads `RESUME` from conf.d but has no `RESUME_OFFSET`;
its init takes `resume_offset` only from the command line or a conf.d
snippet. The package's initramfs hook writes the file's `RESUME_OFFSET` into
the image as that snippet (`conf/conf.d/zz-cushion-swap-resume-offset`).

## What the installer must create

`guest-hibernate-setup.sh` creates it in the guest; `--undo` removes it:

- `guest-hibernate-setup.sh [AREA]` (Sparky's layout): a swap file at least
  the size of RAM as the Cushion area (on Btrfs from `btrfs filesystem
  mkswapfile`, no copy on write), its line in `/etc/fstab` with `noauto` (off
  at boot), and `/etc/initramfs-tools/conf.d/resume` with
  `RESUME=UUID=<file system>` and `RESUME_OFFSET=<first page>` (from
  `filefrag -v -b4096`, or `btrfs inspect-internal map-swapfile -r`). Nothing
  on the kernel command line.
- `--cmdline [AREA]`: the same plus `resume=` and `resume_offset=` on the
  kernel command line (`/etc/default/grub.d/sparky-stereo-resume.cfg`).
- `--partition DEVICE [AREA]` (Daniel's layout): the Cushion area stays a
  swap file; the image goes to the swap partition DEVICE, named in the file
  by `RESUME=UUID=<its UUID>`, with no line in `/etc/fstab`.

Then `update-initramfs -u` and `update-grub`, and a reboot so the initramfs
sets the kernel's resume device. For a swap file initramfs-tools warns "no
matching swap device is available" (it checks the file system); expected.

## Running it

```sh
python3 guest-hibernate.py arm /var/tmp/negative.json --expect-source file --negative --no-hibernate          # must exit 1
python3 guest-hibernate.py arm /var/tmp/neg-dropin.json --expect-source file --negative-dropin --no-hibernate  # must exit 1
python3 guest-hibernate.py arm /var/tmp/neg-switch.json --expect-source file --negative-switch-on --no-hibernate  # must exit 1
python3 guest-hibernate.py arm /var/tmp/arm.json --expect-source file --after-retract   # the VM hibernates and powers off
# start the VM again with exactly the same QEMU command
python3 guest-hibernate.py verify /var/tmp/verify.json                                  # must exit 0
```

`arm` checks: the configuration names a device (with `--expect-source file`,
the file alone and no `resume=` or `resume_offset=` on the command line); the
area is found (a partition by its UUID, or the swap file at that offset among
the Cushion area and fstab's swap lines), holds at least the RAM and is off;
the kernel's `/sys/power/resume` and `resume_offset` equal it (so the
initramfs read the file); the image carries the resume script, the
configuration and, for a swap file, the offset snippet; the package's
`--resume-target` agrees; the generator's drop-in exists and its journal line
says which source decided; `cushion-swap-hibernate.service` is enabled and
wanted by `systemd-hibernate.service`; zram, when present, comes first;
logind's CanHibernate is `yes` for root and `yes` or `challenge` for the
seat's user, and PowerDevil's CanHibernate is `true`. It records the Secure
Boot state, arms (the boot id, a token kept only in `/dev/shm`, a witness
process in its own unit) and calls `systemctl hibernate`.

`--after-retract` first has the daemon deploy the area itself (a hard floor
above what is available, `DEPLOY_HARD_MIB=1048576`, in place of real memory
pressure), then, back on the real thresholds with a quiet window of 20 s,
retract it unused; the journal must show the DEPLOY and the RETRACT ("area
unused") and the log file the retract-check with `area_empty=yes` and
`retract_ok=1`. The settings file is restored afterwards.

`verify` passes only if the same kernel instance came back (boot id, token,
witness), the journal shows the area switched on for the image and switched
off again after resume, the area is off, and logind still offers Hibernate.

The planted faults: `--negative` clears the kernel's resume device;
`--negative-dropin` gives systemd-logind `SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=0`
in a runtime drop-in and restarts it (what a retraction that removed the
generator's drop-in would leave), then puts it back; `--negative-switch-on`
masks `cushion-swap-hibernate.service` for the runtime and asks for
hibernation, which must fail in systemd-sleep, then unmasks it.

`guest-log.py OUT.json` checks the log on the real system: root:adm 0750 and
0640, the file growing, two forced runs of the shipped logrotate file (the
second compressing the first copy), the daemon writing on to the same path
with no gap in the cycle numbers, and no per-cycle line in the journal.

## The 2026-10-10 runs (development VM, sparky-stereo-cushion-swap 0.2.0)

Evidence in `../evidence/cushion-swap-0.2/vm/`. The launcher copies and how
they differ from `sparky-vm.sh` are in `../evidence/vm-launcher.txt`.

- 16 GB: `guest-log.py` passed (cycles 1 to 55 across two rotations, no gap;
  journal: the start and the thresholds only). Idle cost over 120 s: 81
  cycles, 450 ms of CPU.
- 4 GB, Sparky's layout (`/swapfile`, the file alone, no `resume=`): the
  kernel resumed from 254:2 at page 3821568 after a reboot. Negatives: the
  cleared resume device, logind without the bypass (CanHibernate `na`) and
  the masked switch-on ("Failed to find location to hibernate to: Stale file
  handle") each exited 1. Control: with the hook moved aside and the
  initramfs rebuilt, the kernel's offset was 0 against the file's 3821568,
  and `arm` exited 1; with the hook back, 3821568 again. `--after-retract`:
  DEPLOY, then RETRACT of the unused area after 20 s, CanHibernate `yes`
  (root) and `challenge` (ssh user), PowerDevil `true`; the VM hibernated,
  and `verify` passed: same boot, token, witness, `/swapfile switched on for
  the image (from /etc/initramfs-tools/conf.d/resume)`, S4 in and out,
  `after resume: /swapfile was empty, switched off again`.
- 4 GB, Daniel's layout (`/dev/vdb1`, a swap partition in no fstab line,
  named only in the file): two full cycles, `verify` passed both times:
  `/dev/vdb1 switched on for the image`, `after resume: /dev/vdb1 was empty,
  switched off again`.
- Unexplained: after two of the three resumes the guest reset itself 50 to
  70 seconds later (no shutdown in the journal, no pstore record,
  `kernel.panic` 0, the QEMU process unchanged); the third ran on for more
  than four minutes. The first reset left that run's verify JSON empty (its
  output, printed in the guest, is kept as text); the probes now sync their
  JSON. A log of the ICH9 TCO watchdog every 2 seconds through the third
  cycle shows the kernel reloading it every 15 seconds before and after the
  resume, so the watchdog is not the cause. Not identified.

Limits, stated plainly:
- The development VM's firmware has no Secure Boot (OVMF_CODE_4M.fd), so
  these runs are with Secure Boot off; the kernel side under Secure Boot is
  tools/hibernate-bench in the public repository.
- Hibernation fails in the development VM while its virtiofs shares are
  attached (virtio-fs cannot freeze); the hibernate session ran without them.
- The guest's root is ext4: the Btrfs steps are written but did not run.
- `--after-retract` deploys by a forced hard floor, not by real memory
  pressure; the deploy under pressure is measured separately (README of the
  package, "Measured").
