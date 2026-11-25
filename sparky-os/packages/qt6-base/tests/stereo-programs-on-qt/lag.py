#!/usr/bin/env python3
# lag.py STDERR [JSON] -- row 863 part A: reads the stderr of one program run made with WAYLAND_DEBUG=client and the
# r863 probe (or the slideshow's wrapper) and says, for each commit of the stereo windows' parent surface, whether each
# stereo window stood where its widget is in the picture that commit carries.
# (tests/stereo-widget-move/lag.py of row 863, copied so this folder runs on its own, with these additions for
# programs other than the small test:)
#   - A stereo window is a surface declared through kde_stereo_content_manager_v1 (Mesa's create(new id, wl_surface));
#     its place is the place of its subsurface role, made by get_subsurface for that surface on its parent. Places are
#     kept per declared surface, not per role: a program may destroy the role when its widget is hidden and make a new
#     one when it is shown again (VLC Stereo's video surface, its patch 3d-0049). A destroyed role leaves no place; a
#     new one starts at 0,0 ("The initial position is 0, 0").
#   - A set_position takes effect at the parent's next commit (wl_subsurface.set_position: "The scheduled coordinates
#     will take effect whenever the state of the parent surface is applied").
#   - A widget's place at a commit is the latest "R863 flush ... expect=X,Y expect2=X,Y [margins=L,T]" line before it,
#     logged when the main window's update request, expose or scene synchronization begins. With margins (the
#     window's own frame, which a full screen window has not), the window belongs at the widget's place plus the
#     margins of that line; without, plus the offset most commits show ("offset_source" says which). When the second
#     widget's places are the first's in every line, there is one widget.
#   - At a commit between two flush lines that differ, the window counts as placed at the next line's place as well
#     (the program changed its layout, or Qt its frame, after the flush event was logged): those commits are listed in
#     "frame_changes" with the size of the buffer the parent attached in them, which tells which layout the commit's
#     picture has.
#   A misplaced commit reached the screen when the frame callback asked with it was done before the parent's next
#   commit (the compositor drew a frame with it). Callback ids are reused, so each is bound to the commit that asked.
# Prints one JSON object: commits, misplaced (either window), misplaced_shown, longest run of misplaced commits, and the
# time from the first misplaced commit of each run to the commit that placed the window again, in milliseconds.
import json
import re
import sys

LINE = re.compile(r'^\[\s*([0-9:.]+)\]\s*(?:\{[^}]*\}\s*)?(->\s*)?([A-Za-z0-9_]+)[#@](\d+)\.([A-Za-z0-9_]+)\((.*)\)\s*$')
OBJ = re.compile(r'([A-Za-z0-9_]+)[#@](\d+)')
FLUSH = re.compile(r'^R863 flush step=(\d+) expect=(-?\d+),(-?\d+) expect2=(-?\d+),(-?\d+)(?: margins=(-?\d+),(-?\d+))?')


def seconds(stamp):
    parts = stamp.split(':')
    value = 0.0
    for p in parts:
        value = value * 60 + float(p)
    return value


def main():
    path = sys.argv[1]
    stereo = set()         # declared surfaces
    role = {}              # wl_subsurface id -> (child surface, parent surface)
    parent_of = {}         # child surface -> its parent while it has a role
    pending, applied = {}, {}   # child surface -> place
    parent = None
    flushes = []           # (expect pair, margins)
    buffer_size = {}
    parent_buffer = None
    frame_req = None
    commits = []
    cb_owner = {}
    for raw in open(path, errors='replace'):
        raw = raw.rstrip('\n')
        m = FLUSH.match(raw)
        if m:
            expect = ((int(m.group(2)), int(m.group(3))), (int(m.group(4)), int(m.group(5))))
            margins = (int(m.group(6)), int(m.group(7))) if m.group(6) is not None else None
            flushes.append((expect, margins))
            continue
        m = LINE.match(raw)
        if not m:
            continue
        t = seconds(m.group(1))
        req, iface, oid, msg, args = bool(m.group(2)), m.group(3), int(m.group(4)), m.group(5), m.group(6)
        objs = OBJ.findall(args)
        if req and 'stereo_content_manager' in iface and msg in ('create', 'get_stereo_content'):
            stereo.update(int(i) for name, i in objs if name == 'wl_surface')
            for child, par in parent_of.items():
                if child in stereo:
                    parent = par
        elif req and iface == 'wl_subcompositor' and msg == 'get_subsurface':
            ids = [int(i) for _, i in objs]
            if len(ids) == 3:
                sid, child, par = ids
                role[sid] = (child, par)
                parent_of[child] = par
                applied.pop(child, None)
                pending[child] = (0, 0)
                if child in stereo:
                    parent = par
        elif req and iface == 'wl_subsurface' and msg == 'destroy':
            child = role.pop(oid, (None, None))[0]
            if child is not None:
                applied.pop(child, None)
                pending.pop(child, None)
                parent_of.pop(child, None)
        elif req and msg in ('create_buffer', 'create_immed'):
            ids = [int(i) for name, i in objs if name == 'wl_buffer']
            nums = [int(v) for v in re.findall(r'(?<![#@\w])-?\d+', args)]
            if ids:
                # the numbers after the new id: create_buffer(offset, width, height, stride, format),
                # create_immed(width, height, format, flags)
                buffer_size[ids[0]] = (nums[1], nums[2]) if msg == 'create_buffer' else (nums[0], nums[1])
        elif req and iface == 'wl_surface' and msg == 'attach' and oid == parent:
            ids = [int(i) for name, i in objs if name == 'wl_buffer']
            parent_buffer = buffer_size.get(ids[0]) if ids else None
        elif req and iface == 'wl_subsurface' and msg == 'set_position':
            child = role.get(oid, (None, None))[0]
            if child is not None:
                x, y = [int(v) for v in re.findall(r'-?\d+', args)[:2]]
                pending[child] = (x, y)
        elif req and iface == 'wl_surface' and msg == 'frame' and oid == parent:
            ids = [int(i) for _, i in objs]
            frame_req = ids[0] if ids else None
        elif req and iface == 'wl_surface' and msg == 'commit':
            # the roles whose parent this is take their pending places
            for child in list(pending):
                if parent_of.get(child) == oid:
                    applied[child] = pending.pop(child)
            if oid == parent:
                windows = {child: pos for child, pos in applied.items() if child in stereo and parent_of.get(child) == oid}
                if windows and flushes:
                    commits.append({'t': t, 'flush': len(flushes) - 1, 'buffer': parent_buffer, 'applied': dict(windows),
                                    'done': None})
                    if frame_req is not None:
                        cb_owner[frame_req] = len(commits) - 1
                frame_req = None
        elif not req and iface == 'wl_callback' and msg == 'done':
            idx = cb_owner.pop(oid, None)
            if idx is not None and commits[idx]['done'] is None:
                commits[idx]['done'] = t
    widgets = (0, 1) if any(e[0] != e[1] for e, _ in flushes) else (0,)
    with_margins = bool(flushes) and all(mg is not None for _, mg in flushes)

    # the place a window belongs at by flush line f, for widget k (without margins: plus the widget's constant offset)
    def want(f, k, offset):
        (expect, margins) = flushes[f]
        o = margins if with_margins else offset
        return (expect[k][0] + o[0], expect[k][1] + o[1])

    # which declared surface follows which widget (and, without margins, at which constant offset)
    children = sorted({ch for c in commits for ch in c['applied']})

    def votes(ch, k):
        counts = {}
        for c in commits:
            if ch in c['applied']:
                expect, margins = flushes[c['flush']]
                base = margins if with_margins else (0, 0)
                d = (c['applied'][ch][0] - expect[k][0] - base[0], c['applied'][ch][1] - expect[k][1] - base[1])
                counts[d] = counts.get(d, 0) + 1
        return max(counts.items(), key=lambda kv: kv[1]) if counts else ((0, 0), 0)
    match, offset = {}, {}
    for k in widgets:
        left = [ch for ch in children if ch not in match.values()]
        if left:
            best = max(left, key=lambda ch: votes(ch, k)[1])
            match[k], offset[k] = best, votes(best, k)[0]
    frame_changes = []
    for i, c in enumerate(commits):
        nxt = commits[i + 1]['t'] if i + 1 < len(commits) else float('inf')
        c['shown'] = c['done'] is not None and c['done'] <= nxt
        c['mismatch'] = [k for k, ch in match.items() if ch in c['applied'] and c['applied'][ch] != want(c['flush'], k, offset[k])]
        f2 = c['flush'] + 1
        if c['mismatch'] and f2 < len(flushes) and flushes[f2] != flushes[c['flush']]:
            if all(c['applied'][match[k]] == want(f2, k, offset[k]) for k in c['mismatch']):
                frame_changes.append({'t': c['t'], 'flush_before': [list(flushes[c['flush']][0][0]), flushes[c['flush']][1]],
                                      'flush_after': [list(flushes[f2][0][0]), flushes[f2][1]],
                                      'buffer': list(c['buffer']) if c['buffer'] else None,
                                      'positions': [list(v) for v in c['applied'].values()]})
                c['mismatch'] = []
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
        'stereo_surfaces': sorted(stereo),
        'widgets': len(widgets),
        'surfaces_matched': {str(k): v for k, v in match.items()},
        'offsets': {str(k): list(v) for k, v in offset.items()},
        'offset_source': 'margins' if with_margins else 'most common',
        'margins_seen': sorted({tuple(mg) for _, mg in flushes if mg is not None}),
        'frame_changes': frame_changes,
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
