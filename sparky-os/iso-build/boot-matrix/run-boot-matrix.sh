#!/bin/bash
# Boot one ISO under every firmware case, as a CD and as a USB disk, one QEMU run at a time.
#   run-boot-matrix.sh ISO OUTDIR [case ...]
# Cases default to: seabios ovmf sb sb-sbat2024 ia32 sb-2023only sb-2011only. Each run writes
# OUTDIR/<case>-<media>/{menu*.png,t*.png,result.json,serial.log,cmdline.txt}. Nothing touches a display.
set -u
ISO=${1:?iso}; OUT=${2:?outdir}; shift 2
CASES=("$@"); [ ${#CASES[@]} -eq 0 ] && CASES=(seabios ovmf sb sb-sbat2024 ia32 sb-2023only sb-2011only)
HERE=$(cd "$(dirname "$0")" && pwd)
# Enter is sent four times, ten seconds apart, because Secure Boot firmware needs 20 to 35 s before the menu is up
# (a first run with one Enter at 15 s lost it and sat at the GRUB menu); extra Enters land on Plymouth and do nothing.
STEPS=${STEPS:-"10:shot:m10,8:shot:m18,0:key:ret,10:shot:m28,0:key:ret,10:shot:m38,0:key:ret,10:shot:m48,0:key:ret,5:shot:t53,45:shot:t98,45:shot:t143,45:shot:t188,45:shot:t233,45:shot:t278,45:shot:t323"}
mkdir -p "$OUT"
run_pair() {   # both media for one case, one after the other (4 CPU threads for the lane)
  local c=$1
  for m in ${MEDIA:-cd usb}; do
    python3 "$HERE/bootmatrix.py" --iso "$ISO" --fw "$c" --media "$m" --out "$OUT/$c-$m" --steps "$STEPS" ${EXTRA:-} \
      > "$OUT/$c-$m.log" 2>&1
  done
}
for c in "${CASES[@]}"; do run_pair "$c"; done
echo "matrix done: $OUT"
