# Hibernate and resume with the Cushion Swap File: guest test

`guest-hibernate.py` is one self-contained Python 3 script for a disposable
VM (Debian's own commands only). It refuses a container or a machine that
systemd does not identify as a VM. Run it as root.

## What the installer must create

`guest-hibernate-setup.sh [AREA]` creates it in the guest, and
`guest-hibernate-setup.sh --undo [AREA]` removes it again:

- a swap file at least the size of RAM (RAM rounded up to whole GiB); on
  Btrfs made with `btrfs filesystem mkswapfile` (no copy on write);
- its line in `/etc/fstab` with `noauto`, so it stays off at boot
  (`swapon -a` and systemd's swap.target skip it) and the Cushion Swap File
  knows it as its area;
- `resume=UUID=<file system>` and `resume_offset=<first page of the file>`
  on the kernel command line (`/etc/default/grub.d/sparky-stereo-resume.cfg`;
  the offset from `filefrag -v -b4096`, or `btrfs inspect-internal
  map-swapfile -r` on Btrfs);
- `RESUME=UUID=<file system>` in `/etc/initramfs-tools/conf.d/resume`, then
  `update-initramfs -u` and `update-grub`. initramfs-tools warns that no
  swap device matches the UUID (the area is a file, and off); the image
  still carries `scripts/local-premount/resume` and the configuration, and
  the command line's `resume=`/`resume_offset=` decide.

With those in place, sparky-stereo-cushion-swap's generator gives
systemd-logind `SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1`, so Plasma offers
Hibernate while the area is off, and `cushion-swap-hibernate.service`
switches the area on before `systemd-hibernate.service`.

## Running it

```sh
python3 guest-hibernate.py arm /var/tmp/hibernate-negative.json --negative --no-hibernate   # must exit 1
python3 guest-hibernate.py arm /var/tmp/hibernate-arm.json    # checks, arms, hibernates: the VM powers off
# start the VM again with exactly the same QEMU command
python3 guest-hibernate.py verify /var/tmp/hibernate-verify.json   # must exit 0
```

`arm` checks: the area is at least RAM and off; Btrfs no-copy-on-write when
on Btrfs; `resume=` and `resume_offset=` on the command line equal to the
file's device and first page, and the kernel's `/sys/power/resume` and
`resume_offset` agree; the initramfs carries the resume script and its
configuration; zram, when present, has a positive priority (before the
disk swap); logind's CanHibernate is `yes` for root and `yes` or
`challenge` for the seat's user, and PowerDevil's
`org.freedesktop.PowerManagement.CanHibernate` is `true` in the session. It
records the Secure Boot state and then arms: the boot id, a random token
kept only in `/dev/shm`, and a witness process in its own unit; then
`systemctl hibernate`.

`verify` passes only if the same kernel instance came back: the boot id is
unchanged, the token is still in RAM and the witness still runs. It keeps
the journal lines from the hibernation (the Cushion Swap File switching the
area on, the S4 entry and exit, and the area switched off again when the
image left nothing in it).

`--negative` plants one break, the kernel's resume device cleared
(`/sys/power/resume` = `0:0`), and must exit 1 with `negative_detected`;
it writes the original device back.

## The 2026-10-10 run (development VM, 4 GiB of RAM)

Evidence in `../evidence/hibernate/`. The negative exits 1 ("The kernel's
resume device is 0:0, the swap area is on 254:2"). `arm` passes and the VM
hibernates; started again, `verify` passes: boot id unchanged, token in RAM,
witness alive; the journal shows `hibernation: /swapfile switched on for the
image`, `ACPI: PM: Waking up from system sleep state S4`, `System returned
from sleep operation 'hibernate'` and `after resume: /swapfile was empty,
switched off again`.

Limits, stated plainly:
- The development VM's firmware has no Secure Boot (OVMF_CODE_4M.fd, no
  SecureBoot variable), so this run is with Secure Boot off. The kernel's
  side under Secure Boot (hibernation allowed without lockdown, the full
  cycle) is measured by tools/hibernate-bench in the public repository; a
  Secure Boot run of this distribution-side test needs the secboot firmware
  and the edition's key enrolled in the VM.
- Hibernation fails in the development VM while its virtiofs shares are
  attached: virtio-fs cannot freeze (`virtio_pci_freeze returns -95`,
  evidence `attempt1-virtiofs-journal.txt`). The passing run started the
  VM with the same command minus the two shares, for both the hibernation
  and the resume. A machine with virtiofs mounts (some VMs) cannot
  hibernate until that driver gains freeze support.
- The guest's root is ext4: the Btrfs steps (mkswapfile, no copy on write,
  map-swapfile offset) are written in both scripts but did not run here.
- The guest's disk is virtio (rotational=1 in the guest); NVMe and SATA SSD
  timing is not measured here.
