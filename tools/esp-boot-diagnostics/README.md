# ESP absent at boot

`read-only.sh` collects the effective mount configuration and boot journal.
Run it as root for the full journal.
It changes no mounts, services or files.

If `local-fs.target` never became active, inspect all its required mount units, not just `boot-efi.mount`.
A required but masked `tmp.mount` can make systemd abandon the local filesystem target transaction while `sysinit.target` proceeds (it only Wants that target).
An ESP job may or may not have been added before that failure.
An active ESP on one boot does not rule out this configuration bug.

## Disposable QEMU/OVMF regression

Use a headless guest with an fstab ESP and a working serial console/SSH route.
Keep the host and field machines read-only.
The following changes belong only in that disposable guest, with a snapshot taken first:

1.
Save `/etc/fstab`.
Add `tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0`.
Mask `tmp.mount`.
Disable any diagnostic recovery service.
Mask fwupd and its refresh service/timer to exclude them from the test. 2.
Enable systemd manager debug logging in a guest-only `system.conf.d` drop-in.
Reboot the guest.
Capture the full boot journal and run `read-only.sh`.
The red invariant is `local-fs.target` inactive with the debug message `Cannot add dependency job ...
Unit tmp.mount is masked`.
Some boot orders still mount the ESP; retain both outcomes rather than claiming determinism. 3.
Install the fixed kernel-settings package.
Verify the original fstab backup, the commented tmpfs entry, the unchanged ESP entry and the retained tmp mask.
Create a sentinel in the on-disk `/tmp`; reboot the guest. 4.
Require `local-fs.target` and `boot-efi.mount` active, `findmnt /boot/efi` reporting the ESP, no mount at `/tmp`, and the sentinel still present.
Repeat a boot to check the same configuration without another migration.

For the installer path, inspect the packaged Calamares sequence and run its `tmpdisk` command inside the target after writing the generated fstab, before booting that target.
A full interactive installation remains a separate image acceptance check. 