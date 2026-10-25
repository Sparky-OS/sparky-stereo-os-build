#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
# Prove the detector tests reject both unconditional enablement and the old auto rule.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat >"$T/always-on" <<'CONTROL'
#!/bin/bash
mkdir -p "$SPARKY_STEREO_VRAM_BOOST_RUN"
: >"$SPARKY_STEREO_VRAM_BOOST_RUN/enabled"
printf 'decision=on\nreason=negative control\n' >"$SPARKY_STEREO_VRAM_BOOST_RUN/state"
CONTROL
sed 's/if \[ "$mode" = auto \] || \[ "$mode" = yes \]; then/if [ "$mode" = yes ]; then/' \
	"$HERE/../bin/sparky-stereo-vram-boost" >"$T/amd-only"
chmod +x "$T/always-on" "$T/amd-only"
for control in always-on amd-only; do
	if DETECT="$T/$control" bash "$HERE/detect-proof.sh" >"$T/$control.log" 2>&1; then
		cat "$T/$control.log"
		echo "FAIL negative control $control was accepted"
		exit 1
	fi
	cat "$T/$control.log"
	if [ "$control" = always-on ]; then
		grep -q '^FAIL no-dmem mode=auto ' "$T/$control.log"
		grep -q '^FAIL no-region mode=auto ' "$T/$control.log"
	else
		grep -q '^FAIL amd-apu mode=auto ' "$T/$control.log"
		grep -q '^FAIL intel-xe mode=auto ' "$T/$control.log"
	fi
	echo "PASS negative control $control rejected on the required cases"
done
