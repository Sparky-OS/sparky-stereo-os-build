#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""check.py OUT [--control swap-eyes|old-kernel|eye-ignored]: the results of one run.sh run.

Without --control every subtest must pass, the frame-sequential modes kms_frame_sequential lists must be the
detailed timings edid-decode reads as field sequential (size and rate, not the kernel's own reading), and the
guest console must show no KASAN report, BUG or WARNING. With --control the run is a negative control:
  swap-eyes    (IGT --swap-eyes) the eye order subtests must fail, the others pass;
  old-kernel   (a kernel without the series group) no subtest may pass;
  eye-ignored  (a kernel whose composer sends the left half on every frame) the pixel subtests must fail;
  composer-race (a kernel without the composer's user count) back-to-back writeback must fail.
One PASS/FAIL line per check; exit status 1 when a check fails.
"""
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
control = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--control' else None
fails = 0
EYE_ORDER = ['writeback-eye-order', 'crc-eye-order', 'flip-at-pair-boundary']
SUBTESTS = ['mode-listed', 'refused-without-opt-in'] + EYE_ORDER + ['2d-control']


def res(name, ok, detail=''):
    global fails
    print('%-4s %-34s %s' % ('PASS' if ok else 'FAIL', name, detail))
    fails += 0 if ok else 1


console = (out / 'console.log').read_text(errors='replace')
exits = dict(re.findall(r'FS\|igt\|([\w-]+)\|exit=(\d+)', console))
res('booted', 'FS|kernel|' in console, (re.search(r'FS\|kernel\|(.*)', console) or [None, 'no FS|kernel line'])[1].strip())
res('run_finished', 'FS|done' in console)
# kernel lines only (IGT's own lines start with its process name in brackets)
kernel = [l for l in console.splitlines() if re.match(r'^\[ *\d+\.\d{6}\] (?!\()', l)]
bad = [l for l in kernel if re.search(r'(?<![A-Z])BUG:|WARNING:|KASAN:|Oops|unreferenced object', l)]
res('console_clean', not bad, bad[0].strip() if bad else 'no KASAN report, BUG or WARNING')
leaks = re.search(r'FS\|kmemleak\|(\d+) unreferenced', console)
res('no_leaks', leaks is not None and leaks.group(1) == '0',
    f'kmemleak: {leaks.group(1)} unreferenced objects' if leaks else 'no kmemleak scan')


def status(t):
    rc = exits.get(t)
    return {'0': 'pass', '77': 'skip'}.get(rc, 'fail' if rc else 'missing')


for t in SUBTESTS:
    st = status(t)
    if control is None:
        want = {'pass'}
    elif control == 'swap-eyes':
        want = {'fail'} if t in EYE_ORDER else {'pass'}
    elif control == 'old-kernel':
        want = {'fail', 'skip'}
    elif control == 'eye-ignored':
        want = {'fail'} if t in ('writeback-eye-order', 'crc-eye-order', 'flip-at-pair-boundary') else {'pass'}
    elif control == 'composer-race':
        want = {'fail'} if t == 'writeback-eye-order' else {'pass'}
    log = out / f'igt-{t}.log'
    why = ''
    if log.exists():
        text = log.read_text(errors='replace')
        m = re.findall(r'^(?:\(kms_frame_sequential:\d+\) )?(?:INFO|CRITICAL): (.*)$', text, re.M) or \
            re.findall(r'^(Subtest .*|.*(?:Test requirement|Failed assertion|Last errno).*)$', text, re.M)
        why = ' | '.join(x.strip() for x in m[:3])
    res('igt/' + t, st in want, f'{st} (expected {"/".join(sorted(want))}) {why}'[:300])

if control is None:
    decode = (out / 'dp-fs.decode.txt').read_text(errors='replace')
    expected = sorted({(int(w), int(h), round(float(r)))
                       for w, h, r in re.findall(r'DTD \d+:\s+(\d+)x(\d+)\s+([\d.]+) Hz.*field sequential', decode)})
    listed_text = (out / 'igt-mode-listed.log').read_text(errors='replace') if (out / 'igt-mode-listed.log').exists() else ''
    listed = sorted({(int(w), int(h), int(r)) for w, h, r in
                     re.findall(r'frame-sequential mode: (\d+)x(\d+) (\d+) Hz', listed_text)})
    res('modes_equal_edid_decode', bool(expected) and listed == expected, f'edid-decode {expected}, listed {listed}')
    res('edid_conformity', 'EDID conformity: PASS' in decode)

sys.exit(1 if fails else 0)
