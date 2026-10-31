# Temporary ESP tracing

Install these files only on an explicitly authorized test machine.
`install.sh` refuses existing destination files and enables the trace with `--no-reload`.
It neither reloads units nor starts a service, so the running fwupd process stays untouched and the new configuration loads at the next boot.
The drop-in uses two verbosity flags because fwupd 2.1.8 requires both for DEBUG.

The trace service waits for dbus-monitor to enter monitoring mode before declaring readiness.
The fwupd drop-in orders its next start after this trace.
The monitor records only UDisks Filesystem Mount/Unmount calls, UDisks errors, filesystem property changes, login1 SessionNew, and fwupd name-owner changes.
For each filesystem call it also resolves the D-Bus sender's PID.
Boot/service-start, login, login-plus-2/10-second, D-Bus call and mount-state-change snapshots contain only /boot/efi lines from /proc/self/mountinfo.
It runs in the system mount namespace.

After an observed disappearance, the trace waits three seconds for diagnostic events, then requests `systemctl start boot-efi.mount` and checks the result.
Failed remounts are retried at most twice more, ten seconds apart.
It never unmounts a volume, starts fwupd, installs firmware or reboots.
This recovery changes the duration of the symptom and must be accounted for when reading the trace.

The trace log is `/var/log/fwupd-esp-unmount-314/trace.jsonl`, root-only, with two rotated backups and a four MiB limit per file.
Each record contains boot ID, wall-clock and monotonic timestamps.
Daemon debug output stays in the journal.
Read after the operator's next boot:

```sh
sudo journalctl -b -o short-precise -u fwupd.service -u udisks2.service -u boot-efi.mount -u fwupd-esp-unmount-314-trace.service
sudo cat /var/log/fwupd-esp-unmount-314/trace.jsonl
findmnt /boot/efi
```

Remove after collecting the logs:

```sh
sudo systemctl disable --no-reload fwupd-esp-unmount-314-trace.service
trace_pid=$(systemctl show fwupd-esp-unmount-314-trace.service -p MainPID --value)
if test "$trace_pid" -gt 0; then sudo kill -TERM "$trace_pid"; fi
sudo rm /etc/systemd/system/fwupd.service.d/90-order314-trace.conf
sudo rm /etc/systemd/system/fwupd-esp-unmount-314-trace.service
sudo rm /usr/local/libexec/fwupd-esp-unmount-314-trace.py
sudo systemctl daemon-reload
```

Remove only this trace's staging directory and log directory after their evidence has been collected.
Do not remove the containing systemd directories, and do not restart fwupd as part of cleanup.
