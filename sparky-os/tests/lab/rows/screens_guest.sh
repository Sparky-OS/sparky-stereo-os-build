#!/bin/bash
# screens_guest.sh SIDE ARGS...: in the lab22-guest image. Boots the edition kernel (7.3.4-stereo3d18 for both sides: only the compositor differs) with VKMS in QEMU (KVM, no network, no
# display). The virtual HDMI-A output reads a test EDID; the compositor is the root of SIDE (ours: Stereo KWin from the published
# tree; stock: Debian's KWin) and a steps script runs in that root: it starts the compositor, sets modes, shows the test clients,
# and the scanned-out frames are read back. A judge in rows/ judges what came back. Mounts: /bench (tools/vkms-stereo-bench),
# /kern, /kroot (the root of SIDE), /lab (rig and rows).
#
# What it runs is set by the row's environment (the defaults are those of screens-hdmi3d-edid):
#   LAB_PHASE  kwin      the bench's kwin phase, only the layouts in ARGS (fp tab sbs-half sbs-full 2d); judge screens_judge.py
#              deep      rig/guest/deep-steps.sh: 8, 10 and 16 bit ramp clients per layout in ARGS (2d sbs-half), counted level
#                        by level; judge deep_judge.py
#              eyeorder  rig/guest/eyeorder-steps.sh: the bench's eye order matrix on the modes in ARGS (tags of the bench's
#                        eyeorder/steps.sh); judge eyeorder_judge.py
#              anaglyph  rig/guest/anaglyph-steps.sh: the ways to make an output anaglyph, measured (queue row 733's diagnosis)
#   LAB_EDID   stereo-test (default: a 3D television), stereo-test-2d (the same EDID without its HDMI 3D fields, made by the
#              bench's edid/make-2d-edid.py), stereo-eyeorder (the 3D television plus 1920x1080 at 120 Hz, made by
#              rig/guest/make-eyeorder-edid.py)
set -euE
trap 'echo "lab setup error at line $LINENO" >&2; exit 2' ERR
SIDE=$1; shift
PHASE=${LAB_PHASE:-kwin}
EDID=${LAB_EDID:-stereo-test}
W=/tmp/lab-screens
rm -rf $W; mkdir -p $W/tree/bin $W/tree/phases $W/tree/data $W/tree/src $W/g
gcc -O2 -static -o $W/tree/bin/drm-grab /bench/src/drm-grab.c
cp /bench/guest/phases/lib.sh /bench/guest/phases/kwin.sh $W/tree/phases/
cp /bench/edid/stereo-test.bin $W/tree/data/
cp /bench/src/stereo-subsurface.c /bench/src/fullscreen-2d.c /bench/src/deep-ramp.c /bench/src/drm-planelog.c $W/tree/src/
case $EDID in
  stereo-test) ;;
  stereo-test-2d)
    python3 -I /bench/edid/make-2d-edid.py /bench/edid/stereo-test.bin $W/tree/data/stereo-test-2d.bin ;;
  stereo-eyeorder)
    python3 -I /lab/rig/guest/make-eyeorder-edid.py /bench/edid/stereo-full.bin $W/tree/data/stereo-eyeorder.bin ;;
  *) echo "SKIP: unknown LAB_EDID $EDID"; exit 77 ;;
esac
# what the EDID declares, read by edid-decode, for the evidence and the judges
edid-decode --check $W/tree/data/$EDID.bin > /evidence/edid-decode.txt 2>&1 || true
echo "$@" > $W/tree/src/args.txt
case $PHASE in
  kwin)
    # the bench's steps script, with only the layouts of this row shot
    awk -v keep="$*" 'BEGIN{n=split(keep,a," "); for(i=1;i<=n;i++) k[a[i]]=1} /^shoot [a-z0-9-]+ /{ if(!($2 in k)) next } {print}' \
      /bench/guest/phases/kwin-steps.sh > $W/tree/phases/kwin-steps.sh
    JUDGE=screens_judge.py ;;
  deep)     cp /lab/rig/guest/deep-steps.sh $W/tree/phases/kwin-steps.sh; JUDGE=deep_judge.py ;;
  eyeorder) cp /lab/rig/guest/eyeorder-steps.sh $W/tree/phases/kwin-steps.sh; JUDGE=eyeorder_judge.py ;;
  anaglyph) cp /lab/rig/guest/anaglyph-steps.sh $W/tree/phases/kwin-steps.sh; JUDGE=anaglyph_judge.py ;;
  *) echo "SKIP: unknown LAB_PHASE $PHASE"; exit 77 ;;
esac
grep -c '^shoot ' $W/tree/phases/kwin-steps.sh > /evidence/shoots.txt || true
python3 -I /lab/rig/guest/mkguest.py /kern/ours/x $W/g --modules configfs,vkms,9p,9pnet_virtio --modarg vkms=create_default_dev=0 --tree $W/tree --init /lab/rig/guest/init-screens \
  > /evidence/mkguest.log 2>&1 || { echo "SKIP: the guest could not be assembled: $(tail -1 /evidence/mkguest.log)"; exit 77; }
# the kwin phase reads the root's tag "root" and the run folder's tag "out"
mkdir -p /evidence/run
SMP=${LAB_CPUS:-4}; MEM=4096
[ -n "${LAB_MEMORY:-}" ] && MEM=1400
echo "guest: $SMP processors, $MEM MiB (container limits: ${LAB_CPUS:-none} processors, ${LAB_MEMORY:-none})" > /evidence/guest-size.txt
timeout ${LAB_GUEST_TIMEOUT:-1500} qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp $SMP -m $MEM -no-reboot -nodefaults \
  -kernel $W/g/vmlinuz -initrd $W/g/initrd.gz -append "console=ttyS0 panic=-1 loglevel=4 vkms.create_default_dev=0 bench.edid=$EDID" -display none -vga none -serial stdio \
  -virtfs local,path=/kroot,mount_tag=root,security_model=none,readonly=on,id=root \
  -virtfs local,path=/evidence/run,mount_tag=out,security_model=none,id=out \
  > /evidence/console.log 2> /evidence/qemu.log || true
grep -a "STEREO|" /evidence/console.log | tr -d '\r' > /evidence/run/results.txt || true
case $PHASE in
  kwin) python3 /bench/tools/analyze-kwin.py /evidence/run >> /evidence/run/results.txt 2>/evidence/analyze.err || true ;;
  eyeorder) python3 /bench/eyeorder/analyze-eyeorder.py /evidence/run >> /evidence/run/results.txt 2>/evidence/analyze.err || true ;;
esac
# the 8 bit frames of the phases that compare pictures are kept as small PNGs; the 16 bit ones of the deep phase are the judge's
if [ "$PHASE" != deep ]; then
for f in /evidence/run/*.ppm; do [ -e "$f" ] && python3 - "$f" <<'PY'
import sys
from PIL import Image
f = sys.argv[1]
Image.open(f).convert("RGB").save(f[:-4] + ".png", optimize=True)
import os
os.remove(f)
PY
done
fi
exec python3 -I /lab/rows/$JUDGE /evidence/run/results.txt "$@"
