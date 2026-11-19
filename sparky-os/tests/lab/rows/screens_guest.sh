#!/bin/bash
# screens_guest.sh SIDE LAYOUT...: in the lab22-guest image. Boots the edition kernel (7.3.4-stereo3d18 for both sides: only the compositor differs) with VKMS in QEMU (KVM, no network, no
# display). The virtual HDMI-A output reads the test EDID of a 3D television (vkms-stereo-bench, edid/stereo-test.bin; it
# passes edid-decode --check); the compositor is the root of SIDE (ours: Stereo KWin from the published tree; stock: Debian's
# KWin) and the bench's kwin phase sets each listed mode, runs the 2D and the declared test clients, reads the scanned-out frame,
# and rows/screens_judge.py judges the layouts named. Mounts: /bench (tools/vkms-stereo-bench), /kern, /kroot (the root of
# SIDE), /lab (rig and rows).
set -euE
trap 'echo "lab setup error at line $LINENO" >&2; exit 2' ERR
SIDE=$1; shift
W=/tmp/lab-screens
rm -rf $W; mkdir -p $W/tree/bin $W/tree/phases $W/tree/data $W/tree/src $W/g
gcc -O2 -static -o $W/tree/bin/drm-grab /bench/src/drm-grab.c
cp /bench/guest/phases/lib.sh /bench/guest/phases/kwin.sh $W/tree/phases/
cp /bench/edid/stereo-test.bin $W/tree/data/
cp /bench/src/stereo-subsurface.c /bench/src/fullscreen-2d.c $W/tree/src/
# the steps script, with only the layouts of this row shot (the anaglyph case has its own: rig/guest/anaglyph-steps.sh)
if [ "$1" = anaglyph ]; then
  cp /lab/rig/guest/anaglyph-steps.sh $W/tree/phases/kwin-steps.sh
  sed -i 's#/tmp/anaglyph-steps.sh#/tmp/kwin-steps.sh#' $W/tree/phases/kwin-steps.sh
else
awk -v keep="$*" 'BEGIN{n=split(keep,a," "); for(i=1;i<=n;i++) k[a[i]]=1} /^shoot [a-z0-9-]+ /{ if(!($2 in k)) next } {print}' \
  /bench/guest/phases/kwin-steps.sh > $W/tree/phases/kwin-steps.sh
fi
grep -c '^shoot ' $W/tree/phases/kwin-steps.sh > /evidence/shoots.txt || true
python3 -I /lab/rig/guest/mkguest.py /kern/ours/x $W/g --modules configfs,vkms,9p,9pnet_virtio --modarg vkms=create_default_dev=0 --tree $W/tree --init /lab/rig/guest/init-screens \
  > /evidence/mkguest.log 2>&1 || { echo "SKIP: the guest could not be assembled: $(tail -1 /evidence/mkguest.log)"; exit 77; }
# the kwin phase reads the root's tag "root" and the run folder's tag "out"
mkdir -p /evidence/run
SMP=${LAB_CPUS:-4}; MEM=4096
[ -n "${LAB_MEMORY:-}" ] && MEM=1400
echo "guest: $SMP processors, $MEM MiB (container limits: ${LAB_CPUS:-none} processors, ${LAB_MEMORY:-none})" > /evidence/guest-size.txt
timeout 900 qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp $SMP -m $MEM -no-reboot -nodefaults \
  -kernel $W/g/vmlinuz -initrd $W/g/initrd.gz -append "console=ttyS0 panic=-1 loglevel=4 vkms.create_default_dev=0" -display none -vga none -serial stdio \
  -virtfs local,path=/kroot,mount_tag=root,security_model=none,readonly=on,id=root \
  -virtfs local,path=/evidence/run,mount_tag=out,security_model=none,id=out \
  > /evidence/console.log 2> /evidence/qemu.log || true
grep -a "STEREO|" /evidence/console.log | tr -d '\r' > /evidence/run/results.txt || true
[ "$1" = anaglyph ] || python3 /bench/tools/analyze-kwin.py /evidence/run >> /evidence/run/results.txt 2>/evidence/analyze.err || true
for f in /evidence/run/*.ppm; do [ -e "$f" ] && python3 - "$f" <<'PY'
import sys
from PIL import Image
f = sys.argv[1]
Image.open(f).convert("RGB").save(f[:-4] + ".png", optimize=True)
import os
os.remove(f)
PY
done
exec python3 -I /lab/rows/screens_judge.py /evidence/run/results.txt "$@"
