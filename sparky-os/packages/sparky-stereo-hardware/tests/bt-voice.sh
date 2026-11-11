#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# bt-voice-check against fixtures: SPARKY_BT_VOICE_FIXTURE replaces the HCI socket. Run: sh tests/bt-voice.sh (from the recipe folder).
cd "$(dirname "$0")/.." || exit 1
S=bin/sparky-stereo-bt-voice-check
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
adapter() { printf '{"name":"%s","address":"%s","up":%s,"bus":1,"features":[%s],"sco_mtu":%s,"sco_pkts":%s}' "$1" "$2" "$3" "$4" "$5" "$6"; }
BR='191,62,77,250,216,61,123,199'; LE='191,62,77,250,248,61,123,199'
run() { SPARKY_BT_VOICE_FIXTURE=$T/f.json python3 -I $S "$@"; }
printf '[%s]' "$(adapter hci0 00:1A:7D:DA:71:13 true $BR 48 0)" > $T/f.json
run --list | grep -q 'NO VOICE' && ok "an adapter that is up and has no SCO buffers is told" || bad "no verdict for sco_pkts 0"
run --dry-run | grep -q '^sparky-stereo-problems keep sparky-stereo-hardware bt-voice-001a7dda7113 LOCAL18 ' && ok "kept under bt-voice-ADDRESS with LOCAL18" || bad "keep command"
printf '[%s]' "$(adapter hci0 58:00:E3:BC:49:D8 true $BR 50 8)" > $T/f.json
run --list | grep -q 'voice ok' && ok "an adapter with SCO buffers gives no notice" || bad "voice ok"
run --dry-run | grep -q '^sparky-stereo-problems clear sparky-stereo-hardware bt-voice-5800e3bc49d8' && ok "and its notice is cleared" || bad "clear command"
run --dry-run | grep -q '^sparky-stereo-problems keep' && bad "a working adapter must not keep a problem" || ok "no keep for a working adapter"
printf '[%s]' "$(adapter hci0 00:11:22:33:44:55 false $BR 0 0)" > $T/f.json
run --list | grep -q 'not up' && ok "an adapter that is not up is not judged" || bad "not up"
[ -z "$(run --dry-run)" ] && ok "and nothing is kept or cleared for it" || bad "not-up commands"
printf '[%s]' "$(adapter hci0 00:11:22:33:44:66 true $LE 0 0)" > $T/f.json
run --list | grep -q 'LE only' && ok "an LE-only controller (BR/EDR not supported) is not told" || bad "LE only"
printf '[]' > $T/f.json; mkdir -p $T/var/lib/sparky-stereo-problems; : > $T/var/lib/sparky-stereo-problems/sparky-stereo-hardware_bt-voice-aabbccddeeff.json
SPARKY_STEREO_ROOT=$T run --dry-run | grep -q 'clear sparky-stereo-hardware bt-voice-aabbccddeeff' && ok "an unplugged adapter's notice is cleared" || bad "gone adapter"
# the catalogue: LOCAL17 and LOCAL18 exist in all nine languages and LOCAL18 has one %s
for l in en pt_BR de es fr pl ja ko zh_CN zh_TW; do
	grep -q '^LOCAL17=' problems-lang/$l && [ "$(grep '^LOCAL18=' problems-lang/$l | grep -o '%s' | wc -l)" = 1 ] && ok "problems-lang/$l has LOCAL17 and LOCAL18 (one %s)" || bad "problems-lang/$l"
done
exit $failed
