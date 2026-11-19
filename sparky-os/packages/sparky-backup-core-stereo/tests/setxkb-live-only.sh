#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# Sparky SetXKB's autostart unit: skipped on an installed system, run in a live session (ORDER 755, queue 758).
# Run as root in a throwaway container with systemd as PID 1 (docker run -d --cgroupns=private --security-opt writable-cgroups=true
# --tmpfs /run --tmpfs /tmp IMAGE /lib/systemd/systemd). A container cannot replace /proc/cmdline, so the kernel command line
# of the case is given to the user manager through systemd's own $SYSTEMD_PROC_CMDLINE (systemd(1)). Needs systemd, dbus and
# runuser; the package's files are unpacked over the container with dpkg-deb -x, so no dependency of the package is installed.
# usage: setxkb-live-only.sh DEB live|installed
set -uo pipefail
DEB=${1:?path of sparky-backup-core-stereo .deb}
MODE=${2:?live or installed}
UNIT='app-sparky\x2dsetxkb@autostart.service'
fail=0
say() { printf '%s\n' "$*"; }
check() { if [ "$2" = "$3" ]; then say "ok   $1: $3"; else say "FAIL $1: wanted '$2' got '$3'"; fail=1; fi; }
dpkg-deb -x "$DEB" /
say "drop-in shipped: $(ls /usr/lib/systemd/user/app-sparky\\x2dsetxkb@.service.d/ 2>&1 | tr '\n' ' ')"
# a stand-in for the X11 tool the program calls, recording its arguments
printf '#!/bin/sh\necho "setxkbmap $*" >> /tmp/setxkbmap.log\n' > /usr/bin/setxkbmap; chmod 755 /usr/bin/setxkbmap
rm -f /tmp/setxkbmap.log
if [ "$MODE" = live ]; then USERNAME=Live; else USERNAME=tester; fi
id "$USERNAME" >/dev/null 2>&1 || useradd -m -u 1000 "$USERNAME"
UID_=$(id -u "$USERNAME")
if [ "$MODE" = live ]; then CMDLINE='BOOT_IMAGE=/live/vmlinuz boot=live components quiet splash locales=pt_BR.UTF-8 keyboard-layouts=br'; else CMDLINE='BOOT_IMAGE=/boot/vmlinuz root=UUID=0000 ro quiet splash'; fi
mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nEnvironment="SYSTEMD_PROC_CMDLINE=%s"\n' "$CMDLINE" > /etc/systemd/system/user@.service.d/cmdline.conf
systemctl daemon-reload
say "kernel command line given to the session: $CMDLINE"
systemctl start "user@$UID_.service" || { say "FAIL user manager did not start"; exit 1; }
as() { runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR=/run/user/$UID_ "$@"; }
for i in $(seq 30); do as systemctl --user is-system-running >/dev/null 2>&1 && break; sleep 1; done
as systemctl --user daemon-reload
say "unit made by systemd-xdg-autostart-generator: $(as systemctl --user show "$UNIT" -p LoadState,SourcePath | tr '\n' ' ')"
as systemctl --user start "$UNIT"; rc=$?
sleep 2
state=$(as systemctl --user show "$UNIT" -p ActiveState --value)
result=$(as systemctl --user show "$UNIT" -p Result --value)
failed=$(as systemctl --user --failed --no-legend | wc -l)
say "start exit=$rc ActiveState=$state Result=$result failed units=$failed"
as journalctl --user -u "$UNIT" --no-pager -o cat 2>&1 | cut -c1-160 | head -6
if [ "$MODE" = live ]; then
    # the program reads /proc/cmdline itself, which a container cannot replace: it runs, and the layout it picks is the
    # container's, so only the run is checked here
    check "the live session runs the program" yes "$([ -s /tmp/setxkbmap.log ] && echo yes || echo no)"
    check "the unit was not skipped" 0 "$(as journalctl --user -u "$UNIT" --no-pager -o cat | grep -c 'skipped, unmet condition')"
    check "failed user units" 0 "$failed"
else
    check "an installed system has no failed Sparky SetXKB unit" 0 "$failed"
    check "ActiveState" inactive "$state"
    check "the program did not run" "" "$(cat /tmp/setxkbmap.log 2>/dev/null)"
    check "the journal says why it was skipped" 1 "$(as journalctl --user -u "$UNIT" --no-pager -o cat | grep -c 'skipped, unmet condition check ConditionKernelCommandLine=boot=live')"
fi
exit $fail
