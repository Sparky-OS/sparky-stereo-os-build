#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
# The loopback proof's root side, inside a container started with --network none and --cap-add NET_ADMIN: a dummy
# interface in the container's own network namespace (nothing routes out of it), a system bus and Avahi on that interface
# only, the software Cast devices each at its own address and host name, announced as _googlecast._tcp; then the
# person's session as uid 1000 (session.sh). KWin +stereo3d66 from /debs66, and the Throw package from /throwdebs when
# given (the installed rows), else the build tree in /tools/bin with KWin's permission checks off (the development rows).
# Usage: setup.sh OUT_DIR
set -u
OUT=${1:?out dir}
T=/tests
mkdir -p "$OUT/devices"
ip link set lo up
ip link add dummy0 type dummy
ip link set dummy0 multicast on
for n in 1 2 3 4 5; do ip addr add 10.81.0.$n/24 dev dummy0; done
ip link set dummy0 up
ip -brief addr > "$OUT/net.txt"
ip route >> "$OUT/net.txt"
dpkg -i /debs66/*.deb > "$OUT/dpkg-kwin66.log" 2>&1 || { echo "KWin +66 did not install"; tail -20 "$OUT/dpkg-kwin66.log"; exit 1; }
if [ -d /throwdebs ]; then
    dpkg -i /throwdebs/sparky-stereo-throw_*.deb > "$OUT/dpkg-throw.log" 2>&1 || { echo "the Throw package did not install"; tail -20 "$OUT/dpkg-throw.log"; exit 1; }
fi
dpkg-query -W kwin-wayland sparky-stereo-throw > "$OUT/installed.txt" 2>/dev/null
# Avahi on the dummy interface only, IPv4, no workstation record
sed -i -e 's/^#\?allow-interfaces=.*/allow-interfaces=dummy0/' -e 's/^#\?use-ipv6=.*/use-ipv6=no/' \
    -e 's/^#\?publish-workstation=.*/publish-workstation=no/' /etc/avahi/avahi-daemon.conf
grep -q '^allow-interfaces=dummy0' /etc/avahi/avahi-daemon.conf || sed -i '/^\[server\]/a allow-interfaces=dummy0' /etc/avahi/avahi-daemon.conf
mkdir -p /run/dbus
dbus-daemon --system --fork
avahi-daemon -D
sleep 2
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$OUT/devices/key.pem" -out "$OUT/devices/cert.pem" -days 1 -subj /CN=fake-cast-device \
    > /dev/null 2>&1
chown -R 1000:1000 "$OUT"
# address, host, friendly name, model, mode of the fake device, identity
devices=(
    "10.81.0.1 cast-living.local|Living room TV|Chromecast|normal|5d7a9c4e81ab4c3d9e2f000000000081"
    "10.81.0.2 cast-bedroom.local|Bedroom TV|Chromecast Ultra|launch-error|5d7a9c4e81ab4c3d9e2f000000000082"
    "10.81.0.3 cast-study.local|Study screen|Mystery Box 3000|normal|5d7a9c4e81ab4c3d9e2f000000000083"
    "10.81.0.4 cast-hall.local|Hall TV|Chromecast|no-pong|5d7a9c4e81ab4c3d9e2f000000000084"
    "10.81.0.5 cast-den.local|Den TV|Google TV Streamer|normal|5d7a9c4e81ab4c3d9e2f000000000085"
)
for entry in "${devices[@]}"; do
    IFS='|' read -r addrhost name model mode id <<< "$entry"
    addr=${addrhost% *}
    host=${addrhost#* }
    dir="$OUT/devices/$id"
    mkdir -p "$dir"
    chown 1000:1000 "$dir"
    setpriv --reuid=1000 --regid=1000 --clear-groups python3 -I "$T/fake-cast-device.py" --bind "$addr" --log "$dir/device.log" \
        --cert "$OUT/devices/cert.pem" --key "$OUT/devices/key.pem" --out "$dir" --mode "$mode" --name "$name" --model "$model" \
        --udn "$id" --seconds 900 > "$dir/stdout.log" 2>&1 &
    avahi-publish -a -R "$host" "$addr" > "$dir/avahi-address.log" 2>&1 &
    avahi-publish -s -H "$host" "$name" _googlecast._tcp 8009 "id=$id" "fn=$name" "md=$model" "ca=4101" "ve=05" "rs=" \
        > "$dir/avahi-service.log" 2>&1 &
done
sleep 3
avahi-browse -t -r -p _googlecast._tcp > "$OUT/avahi-browse.txt" 2>&1
chown -R 1000:1000 "$OUT"
setpriv --reuid=1000 --regid=1000 --groups=44,125 env HOME="$OUT/home" bash "$T/loopback/session.sh" "$OUT"
