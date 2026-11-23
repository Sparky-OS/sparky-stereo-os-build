import csv, sys, bisect
from pathlib import Path
logdir = Path.home()/'kwin-measure-2026-10-23'
flips = {}
for out in ('eDP-1', 'HDMI-A-1'):
    t = []
    with open(logdir/f'kwin perf statistics {out}.csv') as f:
        r = csv.reader(f); next(r)
        for row in r:
            try: t.append(int(row[1]) / 1e9)
            except (ValueError, IndexError): pass
    t.sort(); flips[out] = t
for root in sys.argv[1:]:
    marks = {}
    for name, ts in csv.reader(open(Path(root).expanduser()/'marks.csv')):
        marks[name] = float(ts)
    print('==', root)
    for name, start in marks.items():
        end = marks.get(name + '-end')
        if end is None or name.endswith('/idle'): continue
        out = name.split('/')[1]
        t = flips[out]
        n = bisect.bisect_left(t, end) - bisect.bisect_left(t, start)
        dur = end - start
        print(f'{name:50} {out:9} kwin frames {n:5} in {dur:5.1f}s = {n/dur:5.2f}/s')
