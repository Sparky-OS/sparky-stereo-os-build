#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# Sparky Welcome's first-run unit under a real user manager (ORDER 63/720): skipped where the Welcome Center carries the
# edition's first page (sparky-stereo-welcome's drop-in), started where it does not.
# Run as root in a throwaway container of an installed system with systemd as PID 1 (docker run -d --cgroupns=private
# --security-opt writable-cgroups=true --tmpfs /run --tmpfs /tmp IMAGE /lib/systemd/systemd), the way
# sparky-backup-core-stereo's tests/setxkb-live-only.sh runs. Needs libpam-systemd and dbus-user-session for the user's
# manager and bus. The person has no display here, so Sparky Welcome's window cannot open; its own mark,
# ~/.config/autostart/sparky-welcome.desktop, written before the window, tells that its first run ran.
# usage: first-run-unit.sh skipped|started [USER]
set -uo pipefail
WANT=${1:?skipped or started}
NAME=${2:-person}
UNIT='app-sparky\x2dwelcome\x2dfirst@autostart.service'
fail=0
say() { printf '%s\n' "$*"; }
check() { if [ "$2" = "$3" ]; then say "ok   $1: $3"; else say "FAIL $1: wanted '$2' got '$3'"; fail=1; fi; }
id "$NAME" >/dev/null 2>&1 || useradd -m -u 1000 "$NAME"
UID_=$(id -u "$NAME"); HOME_=$(getent passwd "$NAME" | cut -d: -f6)
rm -f "$HOME_/.config/autostart/sparky-welcome.desktop"
say "drop-ins shipped: $(ls '/usr/lib/systemd/user/app-sparky\x2dwelcome\x2dfirst@autostart.service.d/' 2>&1 | tr '\n' ' ')"
say "the Welcome Center's first page: $(ls /usr/share/plasma/plasma-welcome/first-pages/00-SparkyStereoOS.qml 2>&1)"
systemctl start "user@$UID_.service" || { say "FAIL user manager did not start"; exit 1; }
as() { runuser -u "$NAME" -- env XDG_RUNTIME_DIR=/run/user/$UID_ "$@"; }
for i in $(seq 30); do as systemctl --user is-system-running >/dev/null 2>&1 && break; sleep 1; done
as systemctl --user daemon-reload
say "unit made by systemd-xdg-autostart-generator: $(as systemctl --user show "$UNIT" -p LoadState,SourcePath | tr '\n' ' ')"
say "its drop-ins: $(as systemctl --user show "$UNIT" -p DropInPaths --value)"
as systemctl --user start "$UNIT"; rc=$?
sleep 9
state=$(as systemctl --user show "$UNIT" -p ActiveState --value)
skipped=$(as journalctl --user -u "$UNIT" --no-pager -o cat | grep -c 'skipped, unmet condition check ConditionPathExists=!/usr/share/plasma/plasma-welcome/first-pages/00-SparkyStereoOS.qml')
mark=$([ -e "$HOME_/.config/autostart/sparky-welcome.desktop" ] && echo yes || echo no)
say "start exit=$rc ActiveState=$state journal 'skipped' lines=$skipped Sparky Welcome's mark written=$mark"
as journalctl --user -u "$UNIT" --no-pager -o cat 2>&1 | cut -c1-200 | head -6
if [ "$WANT" = skipped ]; then
	check "the journal says why it was skipped" 1 "$skipped"
	check "Sparky Welcome's first run did not run (no mark)" no "$mark"
else
	check "the unit was not skipped" 0 "$skipped"
	check "Sparky Welcome's first run ran (its mark)" yes "$mark"
fi
exit $fail
