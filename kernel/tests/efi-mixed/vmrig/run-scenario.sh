#!/bin/bash
# run-scenario.sh NAME N FIRST_KERNEL SYSMAP DEB... : build the installed system (mkscenario.sh, as root in the rig
# image), boot it once on 32-bit OVMF (phase A: update-grub there), then N times through the menu update-grub made.
# Env: W (work dir), R (rig dir), IA32_NOKASLR (optional). Results in $W/runs/vm-NAME.
set -euo pipefail
NAME=$1 N=$2 FIRSTK=$3 SYSMAP=$4; shift 4
S=$W/vmrig/s-$NAME; OUT=$W/runs/vm-$NAME
rm -rf "$S" "$OUT"
mounts=(); args=()
for d in "$@"; do mounts+=(-v "$d:/debs/$(basename "$d"):ro"); args+=("/debs/$(basename "$d")"); done
docker run --rm --name efi-mixed-mkvm --platform linux/amd64 --cpus 2 -e OWNER_UID=$(id -u) -e IA32_NOKASLR="${IA32_NOKASLR:-}" \
	-v "$W:$W" -v "$R:/rig:ro" "${mounts[@]}" ${RIG_IMAGE:-efi-mixed-rig} /rig/vmrig/mkscenario.sh "$S" "$W/vmrig/rootfs-base.tar.zst" "$FIRSTK" "${args[@]}" > "$W/runs/mk-$NAME.log" 2>&1
docker run --rm --name efi-mixed-boot --platform linux/amd64 --cpus 4 --memory 16g --user $(id -u):$(id -g) --device /dev/kvm --group-add $(getent group kvm | cut -d: -f3) \
	-v "$W:$W" -v "$W/fw:/fw:ro" -v "$R:/rig:ro" ${RIG_IMAGE:-efi-mixed-rig} \
	python3 -I /rig/boots.py --loader grub --rw --grub-disk "$S/disk.img" --sysmap "$SYSMAP" --out "$OUT" --count $((N + 1)) --timeout 200 > "$OUT.log" 2>&1
python3 -I - "$OUT" <<'PY'
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1] + '/results.jsonl')]
a, b = rows[0], rows[1:]
print('phase A', a['result'], 'grub lines:'); [print('   ', l) for l in a['grublines']]
c = collections.Counter(r['result'] for r in b)
kas = collections.Counter('nokaslr' in (r.get('cmdline') or '') for r in b if r.get('cmdline'))
hi = sum(1 for r in b if r.get('above_4g'))
print('phase B', dict(c), 'cmdline with nokaslr:', dict(kas), 'trampoline above 4 GiB:', hi,
      'distinct _text:', len({r['text_pa'] for r in b if 'text_pa' in r}))
PY
rm -f "$S/disk.img"
