#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Runs as root in a disposable container (its /etc and /run are the
# container's own). BUILD is the build tree. A private system bus with
# activation of the installed helper, the fake polkit authority, then the
# KCM test saving through KAuth: allowed (files change), denied (no change).
set -u
BUILD=${BUILD:?build tree}
OUT=${OUT:?results folder}
mkdir -p "$OUT"
cmake --install "$BUILD" >"$OUT/install.log" 2>&1 || exit 1
chown "${OWNER:-1000:1000}" "$BUILD/install_manifest.txt"
mkdir -p /run/dbus
conf=$(mktemp)
cat >"$conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path=/run/dbus/system_bus_socket</listen>
  <servicedir>/usr/share/dbus-1/system-services</servicedir>
  <includedir>/usr/share/dbus-1/system.d</includedir>
  <policy context="default">
    <allow user="*"/>
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
dbus-daemon --config-file="$conf" --fork --print-pid >"$OUT/bus.pid"
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
cat /usr/share/dbus-1/system-services/org.sparkylinux.sparkystereo.memory.service >"$OUT/activation.service"
export LANG=C.UTF-8
test_uid=${TEST_UID:-1000}
test_gid=${TEST_GID:-1000}
status=0
mkdir -p /run/sparky-stereo-problems /etc/default
for decision in allow deny; do
	stdbuf -oL "$BUILD/bin/fakepolkit" "$decision" >"$OUT/polkit-$decision.log" 2>&1 &
	polkit=$!
	sleep 1
	touch /etc/default/cushion-swap
	chown "$test_uid:$test_gid" /etc/default/cushion-swap
	SPARKY_KAUTH_TEST=$decision QT_QPA_PLATFORM=offscreen setpriv --reuid="$test_uid" --regid="$test_gid" --init-groups "$BUILD/bin/memorykcmtest" saveThroughKAuth >"$OUT/kcm-$decision.log" 2>&1 || status=1
	rm -f /run/order353-repaired
	cat >/run/sparky-stereo-problems/sparky-stereo-cushion-swap_order353-test.json <<'JSON'
{"package":"sparky-stereo-cushion-swap","key":"order353-test","message":"LOCAL5","args":["/swap/test","test error","/swap/test"],"severity":"failed","text_en":"A test problem with a repair.","repair":[["/usr/bin/touch","/run/order353-repaired"]]}
JSON
	SPARKY_KAUTH_TEST=$decision QT_QPA_PLATFORM=offscreen setpriv --reuid="$test_uid" --regid="$test_gid" --init-groups "$BUILD/bin/memorykcmtest" repairThroughPolkit >"$OUT/repair-$decision.log" 2>&1 || status=1
	grep -q "^CheckAuthorization org.sparkylinux.sparkystereo.problems.repair $decision" "$OUT/polkit-$decision.log" || status=1
	rm -f /run/sparky-stereo-problems/sparky-stereo-cushion-swap_order353-test.json /run/order353-repaired
	grep -q "^CheckAuthorization org.sparkylinux.sparkystereo.memory.savecushion $decision" "$OUT/polkit-$decision.log" || status=1
	kill "$polkit"
	wait "$polkit" 2>/dev/null
	cp /etc/default/cushion-swap "$OUT/cushion-after-$decision.txt"
done
kill "$(cat "$OUT/bus.pid")"
chown -R "${OWNER:-1000:1000}" "$OUT"
exit $status
