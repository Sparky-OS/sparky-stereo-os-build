#!/usr/bin/env python3
# lag.py STDERR [JSON] -- row 863: reads the stderr of one stereo-widget-move run made with WAYLAND_DEBUG=client and says,
# for each commit of the stereo windows' parent surface, whether each stereo window stood where its widget is in the
# picture that commit carries.
#   A stereo window is a surface Mesa declares (kde_stereo_content_manager_v1.create(new id, wl_surface)); its
#   wl_subsurface is the one get_subsurface made for that surface, its parent the surface named there. A set_position
#   takes effect at the parent's next commit (wl_subsurface.set_position: "The scheduled coordinates will take effect
#   whenever the state of the parent surface is applied"). A widget's place at a commit is the test's latest
#   "R863 flush ... expect=X,Y expect2=X,Y" line before it, logged when the main window's update request or expose,
#   whose processing paints and commits, begins. Each stereo subsurface is matched to the widget whose places its
#   positions follow most often.
#   A misplaced commit reached the screen when the frame callback asked with it was done before the parent's next
#   commit (the compositor drew a frame with it). Callback ids are reused, so each is bound to the commit that asked.
# Prints one JSON object: commits, misplaced (either window), misplaced_shown, longest run of misplaced commits, and the
# time from the first misplaced commit of each run to the commit that placed the window again, in milliseconds.
import json
import re
import sys

LINE = re.compile(r'^\[\s*([0-9:.]+)\]\s*(?:\{[^}]*\}\s*)?(->\s*)?([A-Za-z0-9_]+)[#@](\d+)\.([A-Za-z0-9_]+)\((.*)\)\s*$')
OBJ = re.compile(r'([A-Za-z0-9_]+)[#@](\d+)')
FLUSH = re.compile(r'^R863 flush step=(\d+) expect=(-?\d+),(-?\d+) expect2=(-?\d+),(-?\d+)')


def seconds(stamp):
    parts = stamp.split(':')
    value = 0.0
    for p in parts:
        value = value * 60 + float(p)
    return value


def main():
    path = sys.argv[1]
    stereo_surfaces = set()
    sub_of = {}            # wl_subsurface id -> (child surface, parent surface)
    pending, applied = {}, {}
    parent = None
    expect = None
    frame_req = None
    commits = []
    cb_owner = {}
    for raw in open(path, errors='replace'):
        raw = raw.rstrip('\n')
        m = FLUSH.match(raw)
        if m:
            expect = ((int(m.group(2)), int(m.group(3))), (int(m.group(4)), int(m.group(5))))
            continue
        m = LINE.match(raw)
        if not m:
            continue
        t = seconds(m.group(1))
        req, iface, oid, msg, args = bool(m.group(2)), m.group(3), int(m.group(4)), m.group(5), m.group(6)
        objs = OBJ.findall(args)
        if req and 'stereo_content_manager' in iface and msg in ('create', 'get_stereo_content'):
            stereo_surfaces.update(int(i) for name, i in objs if name == 'wl_surface')
            for sid, (child, par) in sub_of.items():
                if child in stereo_surfaces:
                    parent = par
        elif req and iface == 'wl_subcompositor' and msg == 'get_subsurface':
            ids = [int(i) for _, i in objs]
            if len(ids) == 3:
                sub_of[ids[0]] = (ids[1], ids[2])
                pending.pop(ids[0], None)
                applied.pop(ids[0], None)
                if ids[1] in stereo_surfaces:
                    parent = ids[2]
        elif req and iface == 'wl_subsurface' and msg == 'set_position':
            x, y = [int(v) for v in re.findall(r'-?\d+', args)[:2]]
            pending[oid] = (x, y)
        elif req and iface == 'wl_surface' and msg == 'frame' and oid == parent:
            ids = [int(i) for _, i in objs]
            frame_req = ids[0] if ids else None
        elif req and iface == 'wl_surface' and msg == 'commit':
            # the subsurfaces whose parent this is take their pending positions
            for sid in list(pending):
                if sub_of.get(sid, (None, None))[1] == oid:
                    applied[sid] = pending.pop(sid)
            if oid == parent:
                stereo_subs = {sid: pos for sid, pos in applied.items() if sub_of[sid][0] in stereo_surfaces}
                if stereo_subs and expect is not None:
                    commits.append({'t': t, 'expect': expect, 'applied': dict(stereo_subs), 'done': None})
                    if frame_req is not None:
                        cb_owner[frame_req] = len(commits) - 1
                frame_req = None
        elif not req and iface == 'wl_callback' and msg == 'done':
            idx = cb_owner.pop(oid, None)
            if idx is not None and commits[idx]['done'] is None:
                commits[idx]['done'] = t
    # which subsurface follows which widget, and at which constant offset: a frame Qt draws itself around the window
    # (client-side decorations) puts the subsurface at the widget's place plus the frame's margins
    subs = sorted({sid for c in commits for sid in c['applied']})
    def diffs(sid, k):
        counts = {}
        for c in commits:
            if sid in c['applied']:
                d = (c['applied'][sid][0] - c['expect'][k][0], c['applied'][sid][1] - c['expect'][k][1])
                counts[d] = counts.get(d, 0) + 1
        return max(counts.items(), key=lambda kv: kv[1]) if counts else ((0, 0), 0)
    match, offset = {}, {}
    for k in (0, 1):
        left = [sid for sid in subs if sid not in match.values()]
        if left:
            best = max(left, key=lambda sid: diffs(sid, k)[1])
            match[k], offset[k] = best, diffs(best, k)[0]
    for i, c in enumerate(commits):
        nxt = commits[i + 1]['t'] if i + 1 < len(commits) else float('inf')
        c['shown'] = c['done'] is not None and c['done'] <= nxt
        c['mismatch'] = [k for k, sid in match.items() if sid in c['applied']
                         and (c['applied'][sid][0] - c['expect'][k][0], c['applied'][sid][1] - c['expect'][k][1]) != offset[k]]
    runs, cur, start = [], 0, None
    for c in commits:
        if c['mismatch']:
            if cur == 0:
                start = c['t']
            cur += 1
        elif cur:
            runs.append((cur, (c['t'] - start) * 1000))
            cur = 0
    if cur:
        runs.append((cur, None))
    out = {
        'stereo_surfaces': sorted(stereo_surfaces),
        'subsurfaces_matched': {str(k): v for k, v in match.items()},
        'offsets': {str(k): list(v) for k, v in offset.items()},
        'commits': len(commits),
        'misplaced': sum(bool(c['mismatch']) for c in commits),
        'misplaced_first': sum(0 in c['mismatch'] for c in commits),
        'misplaced_second': sum(1 in c['mismatch'] for c in commits),
        'misplaced_shown': sum(bool(c['mismatch']) and c['shown'] for c in commits),
        'shown_commits': sum(c['shown'] for c in commits),
        'runs': len(runs),
        'longest_run': max((r[0] for r in runs), default=0),
        'ms_to_place': [round(r[1], 3) if r[1] is not None else None for r in runs],
    }
    text = json.dumps(out)
    print(text)
    if len(sys.argv) > 2:
        open(sys.argv[2], 'w').write(text + '\n')


if __name__ == '__main__':
    main()
