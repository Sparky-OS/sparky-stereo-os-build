#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""check.py OUT: the two runs of run.sh. One PASS/FAIL line per check; exit status 1 on a FAIL."""
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
fails = 0


def res(name, ok, detail):
    global fails
    print('%-4s %-36s %s' % ('PASS' if ok else 'FAIL', name, detail))
    fails += 0 if ok else 1


def guest(s):
    text = (out / f'guest-stereo-{s}.log').read_text(errors='replace')
    modes = [l.split('|') for l in re.findall(r'^MODE\|.*$', text, re.M)]
    sets = [l.split('|') for l in re.findall(r'^SET\|.*$', text, re.M)]
    return text, modes, sets


def traced(s):
    text = (out / f'qemu-stereo-{s}.log').read_text(errors='replace')
    return [int(m) for m in re.findall(r'virtio_gpu_cmd_set_scanout_stereo id \d+, layout (\d+)', text)]


text, modes, sets = guest('on')
layouts = traced('on')
three_d = sorted({int(m[6]) for m in modes if int(m[6])})
res('booted_build', 'KERNEL|' in text, re.search(r'^KERNEL\|(.*)$', text, re.M).group(1) if 'KERNEL|' in text else 'no KERNEL line')
res('stereo_modes_listed', bool(three_d), f'{len(modes)} modes, 3D structures {three_d}')
ok3d = [s for s in sets if int(s[1]) and s[6] == '0']
res('stereo_sets_succeed', bool(ok3d) and len(ok3d) == len([s for s in sets if int(s[1])]),
    '; '.join(f'3d={s[1]} {s[2]}x{s[3]} fb {s[4]}x{s[5]} rc={s[6]}' for s in sets if int(s[1])))
res('command_per_stereo_set', all(int(s[1]) in layouts for s in ok3d), f'QEMU traced layouts {layouts}')
last2d = [s for s in sets if not int(s[1])]
res('stereo_none_after_2d_set', bool(last2d) and last2d[-1][6] == '0' and bool(layouts) and layouts[-1] == 0,
    f'2D set rc={last2d[-1][6] if last2d else "?"}, last traced layout {layouts[-1] if layouts else "none"}')
text, modes, sets = guest('off')
res('control_no_stereo_modes', bool(modes) and not any(int(m[6]) for m in modes), f'{len(modes)} modes, none 3D expected')
res('control_no_stereo_command', traced('off') == [], f'QEMU traced {traced("off")}')
sys.exit(fails > 0)
