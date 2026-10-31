#!/bin/bash
set -euo pipefail
cd /home/tester/order314
exec > matrix.txt 2>&1
trap 'systemctl start boot-efi.mount; if [[ -n ${monitor_pid:-} ]]; then kill "$monitor_pid"; wait "$monitor_pid" || true; fi' EXIT
dbus-monitor --system "type='method_call',interface='org.freedesktop.UDisks2.Filesystem'" > dbus-matrix.log 2>&1 &
monitor_pid=$!
sleep 1
for case in stock-control stock-fault rebuilt-fault patched-fault patched-control; do
    systemctl start boot-efi.mount
    mountpoint -q /boot/efi
    printf 'CASE %s BEFORE\n' "$case"
    awk '$5 == "/boot/efi"' /proc/self/mountinfo
    envargs=(FWUPD_SYSFSFWDIR=/opt/order314/sysfw)
    case "$case" in
        *-fault) envargs+=(LD_PRELOAD=/home/tester/order314/stale-mountpoints.so);;
    esac
    case "$case" in
        rebuilt-*) envargs+=(LD_LIBRARY_PATH=/home/tester/order314/red-lib);;
        patched-*) envargs+=(LD_LIBRARY_PATH=/home/tester/order314/green-lib);;
    esac
    env "${envargs[@]}" /usr/libexec/fwupd/fwupd --verbose --verbose --immediate-exit > "$case.log" 2>&1
    mounted=0
    mountpoint -q /boot/efi && mounted=1
    printf 'CASE %s AFTER mounted=%s\n' "$case" "$mounted"
    awk '$5 == "/boot/efi"' /proc/self/mountinfo
    case "$case" in
        stock-fault|rebuilt-fault)
            test "$mounted" = 0
            grep -q 'UDISKS REPLY Mount org.freedesktop.UDisks2.Error.AlreadyMounted' "$case.log"
            grep -q 'UDISKS REPLY Unmount OK' "$case.log";;
        patched-fault)
            test "$mounted" = 1
            grep -q 'UDISKS REPLY Mount org.freedesktop.UDisks2.Error.AlreadyMounted' "$case.log"
            ! grep -q 'UDISKS CALL Unmount' "$case.log";;
        *) test "$mounted" = 1;;
    esac
    echo "PASS expected outcome: $case"
done
printf 'ALL FIVE CASES PASS\n'
