#!/usr/bin/env python3
# lag-selftest.py STDERR -- the known bad cases for this folder's lag.py (row 863 part A): a real wire log in which Qt
# changed its frame (a program run with "full" twice, so the probe's flush lines carry margins 3,30 and 0,0) is copied
# with one change at a time, and lag.py must count the change as misplaced:
#   unchanged      no misplaced commit (the run as it was)
#   off40          one set_position of the stereo subsurface, in a still part of the run, moved by 40,40
#   other-frame    the same set_position put where the other frame would place it (the widget's place plus the margins
#                  of the full-screen state, 0,0, while Qt drew its frame): the leniency at a frame change must not apply
#   frame-change   the set_positions before a commit lag.py accepted with the next flush line's frame moved by 40,40
# Prints one line per case and exits 1 when a case is not caught (or the unchanged run is not clean).
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LAG = Path(__file__).resolve().parent / 'lag.py'
POS = re.compile(r'^(\[\s*([0-9:.]+)\].*wl_subsurface#(\d+)\.set_position\()(-?\d+), (-?\d+)(\).*)$')


def lag(lines):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
        f.write('\n'.join(lines) + '\n')
    r = subprocess.run([sys.executable, '-I', str(LAG), f.name], capture_output=True, text=True)
    Path(f.name).unlink()
    return json.loads(r.stdout)


def seconds(stamp):
    v = 0.0
    for part in stamp.split(':'):
        v = v * 60 + float(part)
    return v


def main():
    lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
    base = lag(lines)
    surface = str(base['surfaces_matched']['0'])
    # the subsurface roles of the matched surface (get_subsurface(new id wl_subsurface#ROLE, wl_surface#SURFACE, ...))
    roles = set(re.findall(r'get_subsurface\(new id wl_subsurface#(\d+), wl_surface#' + surface + r',', '\n'.join(lines)))
    margins = [tuple(m) for m in base['margins_seen']]
    framed = max(margins)
    pos = [i for i, l in enumerate(lines) if (m := POS.match(l)) and m.group(3) in roles]
    rc = 0
    print(f"{'caught' if base['misplaced'] == 0 else 'NOT CLEAN'}  unchanged: misplaced {base['misplaced']}, frame changes {len(base['frame_changes'])}")
    rc |= base['misplaced'] != 0
    # a set_position in a still part: the first one after the first step's report line
    first_step = next(i for i, l in enumerate(lines) if l.startswith('R863 step=1 '))
    still = next(i for i in pos if i > first_step)

    def moved(idx_list, fn):
        out = list(lines)
        for i in idx_list:
            m = POS.match(out[i])
            x, y = fn(int(m.group(4)), int(m.group(5)))
            out[i] = f'{m.group(1)}{x}, {y}{m.group(6)}'
        return out

    cases = [('off40', moved([still], lambda x, y: (x + 40, y + 40)))]
    other = tuple(min(margins))
    cases.append(('other-frame', moved([still], lambda x, y: (x - framed[0] + other[0], y - framed[1] + other[1]))))
    if base['frame_changes']:
        t = base['frame_changes'][0]['t']
        before = [i for i in pos if seconds(POS.match(lines[i]).group(2)) < t]
        # every set_position since the commit before that one
        tail = [i for i in before if seconds(POS.match(lines[i]).group(2)) > t - 0.2]
        cases.append(('frame-change', moved(tail or before[-1:], lambda x, y: (x + 40, y + 40))))
    else:
        print('NOT RUN  frame-change: the log has no commit placed with the next flush line\'s frame')
        rc = 1
    for name, mutated in cases:
        r = lag(mutated)
        ok = r['misplaced'] > 0
        rc |= not ok
        print(f"{'caught' if ok else 'NOT CAUGHT'}  {name}: misplaced {r['misplaced']}, shown {r['misplaced_shown']}")
    sys.exit(rc)


if __name__ == '__main__':
    main()
