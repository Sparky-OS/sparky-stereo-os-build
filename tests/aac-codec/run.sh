#!/bin/bash
# Check a built pipewire-bluez5-codec-aac against the PipeWire of Debian testing, without a Bluetooth device (row 944):
# the codec installs with apt beside Debian's libspa-0.2-bluetooth, PipeWire's Bluetooth monitor loads it, a 1 kHz tone
# survives the codec's encode and decode, and the decoder refuses a buffer smaller than a frame (codec-check.c).
# With a predecessor .deb as well, apt's answer to it and the same three checks on its plugin are printed beside them.
# Usage: run.sh OUT NEW.deb [PREDECESSOR.deb]
# Environment: DOCKER_HOST (the caller's socket), NAME_PREFIX (containers and the image, default aac-codec-check-),
#   BASE (default debian:testing), CONTAINER_IDS (a file each container's id is appended to before it is removed).
# Exit 0 only when every check of NEW passes; the predecessor's rows are facts for the reader, never the verdict.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../.." && pwd)
OUT=${1:?usage: run.sh OUT NEW.deb [PREDECESSOR.deb]}
NEW=${2:?usage: run.sh OUT NEW.deb [PREDECESSOR.deb]}
OLD=${3:-}
PREFIX=${NAME_PREFIX:-aac-codec-check-}
BASE=${BASE:-debian:testing}
[[ $PREFIX =~ ^[a-z0-9][a-z0-9_.-]*$ ]] || { echo "NAME_PREFIX must be a plain container name prefix" >&2; exit 2; }
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 2; }
OUT=$(realpath "$OUT")
mkdir "$OUT/debs"
cp "$NEW" "$OUT/debs/new.deb"
[ -z "$OLD" ] || cp "$OLD" "$OUT/debs/old.deb"
forget() {
	[ -z "${CONTAINER_IDS:-}" ] || docker inspect -f '{{.Id}}' "$1" >>"$CONTAINER_IDS"
	docker rm "$1" >/dev/null
}
prep=${PREFIX}prep image=${PREFIX}image:1 check=${PREFIX}run
date -u +%FT%TZ >"$OUT/started.txt"
# 1. Debian's PipeWire, the matching source's codec header, the check built, the codec installed by apt (network on)
docker run --name "$prep" --ulimit core=1 --cpus 4 --platform linux/amd64 \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$tree/tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	-v "$here":/check:ro -v "$OUT":/out -e HOSTID="$(id -u):$(id -g)" "$BASE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
sed -i "s/^Types: deb$/Types: deb deb-src/; s/^Components: main$/Components: main contrib non-free non-free-firmware/" \
	/etc/apt/sources.list.d/debian.sources
apt-get -q update >/out/prep-update.log 2>&1
grep -h -E "^(Date|Valid-Until):" /var/lib/apt/lists/*_dists_testing_InRelease >/out/debian-index.txt || true
apt-get -y -q --no-install-recommends install pipewire libspa-0.2-bluetooth libpipewire-0.3-dev gcc libc6-dev pkgconf \
	dpkg-dev >/out/prep-install.log 2>&1
version=$(dpkg-query -W -f="\${Version}" libspa-0.2-bluetooth)
mkdir /opt/src && cd /opt/src
apt-get source -q --download-only --only-source "pipewire=$version" >/out/prep-source.log 2>&1
dpkg-source -x pipewire_*.dsc pw >>/out/prep-source.log 2>&1
cc -O1 -g -Wall /check/codec-check.c -I /opt/src/pw/spa/plugins/bluez5 $(pkg-config --cflags --libs libpipewire-0.3) -lm \
	-o /opt/codec-check >/out/prep-compile.log 2>&1
rc=0; apt-get -y -q install /out/debs/new.deb >/out/install-new.log 2>&1 || rc=$?; echo "$rc" >/out/install-new.rc
if [ -e /out/debs/old.deb ]; then
	rc=0; apt-get -s -q install /out/debs/old.deb >/out/install-old.log 2>&1 || rc=$?; echo "$rc" >/out/install-old.rc
	dpkg-deb -x /out/debs/old.deb /opt/old
	cp -a /usr/lib/x86_64-linux-gnu/spa-0.2 /opt/spa-old
	cp /opt/old/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-codec-bluez5-aac.so /opt/spa-old/bluez5/
fi
dpkg-query -W pipewire libspa-0.2-bluetooth libpipewire-0.3-0t64 pipewire-bluez5-codec-aac libfdk-aac2 >/out/versions.txt 2>&1 || true
dpkg-deb -f /out/debs/new.deb Version Depends >/out/new-control.txt
[ ! -e /out/debs/old.deb ] || dpkg-deb -f /out/debs/old.deb Version Depends >/out/old-control.txt
chown -R "$HOSTID" /out' >"$OUT/prep.console.log" 2>&1 || { forget "$prep"; echo "prepare failed: $OUT/prep.console.log" >&2; exit 2; }
docker commit "$prep" "$image" >/dev/null
forget "$prep"
# 2. the checks, offline, as the caller's user, each plugin in its own run
docker run --name "$check" --ulimit core=1 --cpus 4 --network none --pull=never --user "$(id -u):$(id -g)" -e HOME=/tmp \
	-v "$OUT":/out "$image" bash -c '
for which in new old; do
	if [ "$which" = old ]; then [ -d /opt/spa-old ] || continue; export SPA_PLUGIN_DIR=/opt/spa-old; fi
	PIPEWIRE_DEBUG=spa.bluez5.codecs:4 /opt/codec-check monitor >/out/$which-monitor.txt 2>&1; echo $? >/out/$which-monitor.rc
	/opt/codec-check codec >/out/$which-codec.txt 2>&1; echo $? >/out/$which-codec.rc
	/opt/codec-check bounds >/out/$which-bounds.txt 2>&1; echo $? >/out/$which-bounds.rc
done' >"$OUT/run.console.log" 2>&1 || true
forget "$check"
docker rmi "$image" >/dev/null
date -u +%FT%TZ >"$OUT/finished.txt"
# 3. the verdict, from the files
fail=0
row() { printf '%-4s %-8s %s\n' "$1" "$2" "$3" | tee -a "$OUT/verdict.txt"; }
[ "$(cat "$OUT/install-new.rc")" = 0 ] && row new install "PASS apt installed it beside $(grep '^libspa-0.2-bluetooth' "$OUT/versions.txt" | cut -f2)" ||
	{ row new install "FAIL apt refused it (install-new.log)"; fail=1; }
loaded() { grep -h -o 'loaded media codec aac from api.codec.bluez5.media.aac[^ ]*' "$OUT/$1-monitor.txt" | head -1; }
if [ -n "$(loaded new)" ]; then row new monitor "PASS PipeWire's Bluetooth monitor: $(loaded new)"; else row new monitor "FAIL no codec line (new-monitor.txt)"; fail=1; fi
[ "$(cat "$OUT/new-codec.rc")" = 0 ] && row new codec "PASS $(grep -c '^tone: .* ok$' "$OUT/new-codec.txt") channels carry the tone" ||
	{ row new codec "FAIL (new-codec.txt)"; fail=1; }
[ "$(cat "$OUT/new-bounds.rc")" = 0 ] && row new bounds "$(grep '^bounds: PASS' "$OUT/new-bounds.txt")" || { row new bounds "FAIL $(grep '^bounds: buffer' "$OUT/new-bounds.txt")"; fail=1; }
if [ -n "$OLD" ]; then
	[ "$(cat "$OUT/install-old.rc")" = 0 ] && row old install "apt would install it" ||
		row old install "apt refuses it: $(grep -m1 -E 'Depends|unmet|broken' "$OUT/install-old.log" | sed 's/^ *//')"
	row old monitor "$( [ -n "$(loaded old)" ] && echo "loaded: $(loaded old)" || echo "no codec line (old-monitor.txt)")"
	row old codec "$(grep -E '^(codec|interface): ' "$OUT/old-codec.txt" | tail -1)"
	row old bounds "$(grep '^bounds: buffer' "$OUT/old-bounds.txt")"
fi
row all verdict "$([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
