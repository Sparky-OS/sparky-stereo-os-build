#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Root in a disposable container only: real KAuth helper on a private system bus.
set -eu
: "${BUILD:?}" "${OUT:?}"
mkdir -p "$OUT" /run/dbus
cmake --install "$BUILD" >"$OUT/install.log" 2>&1
id proof >/dev/null 2>&1 || useradd -m proof
uid=$(id -u proof)
gid=$(id -g proof)
conf=$(mktemp)
cat >"$conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>system</type><listen>unix:path=/run/dbus/system_bus_socket</listen>
<servicedir>/usr/share/dbus-1/system-services</servicedir><includedir>/usr/share/dbus-1/system.d</includedir>
<policy context="default"><allow user="*"/><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
dbus-daemon --config-file="$conf" --fork --print-pid >"$OUT/bus.pid"
trap 'kill "$(cat "$OUT/bus.pid")"; rm -f "$conf"' EXIT
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
export LANG=C.UTF-8
status=0
for decision in allow deny; do
    "$BUILD/bin/fakepolkit" "$decision" >"$OUT/polkit-$decision.log" 2>&1 &
    authority=$!
    sleep 1
    printf '# a person\047s comment\nSPARKY_STEREO_VRAM_BOOST=no\n' >/etc/default/sparky-stereo-vram-boost
    chmod 644 /etc/default/sparky-stereo-vram-boost
    mkdir -p "$OUT/shots"; chmod 777 "$OUT/shots"
    SPARKY_KAUTH_TEST=$decision SCREENSHOT_DIR="$OUT/shots" QT_QUICK_BACKEND=software QT_QPA_PLATFORM=offscreen \
        setpriv --reuid="$uid" --regid="$gid" --init-groups "$BUILD/bin/vramkcmtest" >"$OUT/$decision.log" 2>&1 || status=1
    kill "$authority"; wait "$authority" 2>/dev/null || true
    grep -q "CheckAuthorization org.sparkylinux.sparkystereo.graphics.savevram $decision" "$OUT/polkit-$decision.log" || status=1
done
exit "$status"
