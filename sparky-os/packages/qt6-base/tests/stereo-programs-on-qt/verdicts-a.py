#!/usr/bin/env python3
# verdicts-a.py RESULTS... -- row 863 part A: the verdicts of the program cases (analyze-prog.py's JSON files), Qt's
# frame row (frame-analyze.py's) and the known bad cases, found in the RESULTS folders.
#
# A program is judged as a pair of runs, NAME-pub (the published set) and NAME-q24 (the same image with the staged Qt):
#  - placement, on each run, at every captured step where the probe sees the 3D widget shown: the capture is a pair (KWin
#    says stereo), the eyes differ somewhere and only inside the widget's rectangle, the probe found the stereo window
#    at the widget's place (placed=1); where the widget is hidden the capture is one picture; and lag.py (this folder's,
#    run again on the run's wire log) counts no commit of the parent that put the stereo window away from its widget.
#    A placement failure on +24 that the published run does not have fails the row ("a subsurface left at an old
#    place ... is a failure, not a tolerated difference"); the same failure on both runs (the same steps and kinds, the
#    wire log's misplaced commits on both or on neither) is a FINDING of the published set, printed first, and is not
#    a difference +24 makes.
#  - the program's own measure (analyze-prog.py --measure): it must say the same on both runs. Failing the same way on
#    both, it is a finding of the program on the published set, listed, and the row stands (+24 shows what +23 showed).
#  - the pixels of each eye that differ between the two runs are listed per step.
# Known bad cases (bad-*) must be caught by a placement measure; Qt's frame rows must agree in every step and their
# known bad case must not. Prints one line per row and exits 1 when a row is not as expected.
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def fields(line):
    out = {}
    for word in (line or '').split():
        if '=' in word:
            k, v = word.split('=', 1)
            out[k] = v
    return out


def relag(d, folder):
    stderr = folder / d['case'] / 'stderr.txt'
    if stderr.exists():
        r = subprocess.run([sys.executable, '-I', str(HERE / 'lag.py'), str(stderr)], capture_output=True, text=True)
        try:
            d['lag'] = json.loads(r.stdout)
        except ValueError:
            d['lag'] = {'error': r.stderr[-300:]}


def shown(s):
    f = fields(s.get('probe'))
    return 'expect' in f and f.get('visible') == '1'


def placement(d):
    bad = []
    for s in d['steps']:
        f = fields(s.get('probe'))
        if shown(s):
            if not s.get('stereo_capture'):
                bad.append(f"step {s['step']}: one picture where the 3D area is shown")
            elif s.get('pair_px', 0) == 0:
                bad.append(f"step {s['step']}: the eyes are the same")
            if s.get('pair_inside') is False:
                bad.append(f"step {s['step']}: the eyes differ outside the widget {s.get('widget_rect')}: {s.get('pair_bbox')}")
            if f.get('placed') == '0':
                bad.append(f"step {s['step']}: the probe found the stereo window at {f.get('window')}, the widget at {f.get('expect')}")
        elif s.get('stereo_capture') and s.get('pair_px', 0) > 0 and 'expect' in f:
            bad.append(f"step {s['step']}: a pair while the 3D area is hidden")
    lag = d.get('lag') or {}
    if lag.get('error') or 'misplaced' not in lag:
        bad.append(f"wire log not read: {lag.get('error')}")
    elif lag['misplaced']:
        bad.append(f"wire log: {lag['misplaced']} commits put the stereo window away from its widget, {lag['misplaced_shown']} reached the screen (runs {lag['ms_to_place']} ms)")
    if not any(shown(s) for s in d['steps']):
        bad.append('no step shows the 3D area')
    return bad


def measure(d):
    # per step: (judged, ok, summary)
    out = {}
    for s in d['steps']:
        m = s.get('measure')
        if m is None or not shown(s):
            continue
        if d['case'].startswith('kubrick') and s['step'] == 0:
            # before the probe's click Kubrick's demo animates; the shim records still frames only, so the record
            # analysed is not the captured frame
            out[s['step']] = (False, True, f"median {m.get('median_abs_px')} px (the demo animates: not judged)")
            continue
        if m.get('offscreen'):
            out[s['step']] = (False, True, f"the video box {m.get('box')} is partly off the screen: not judged")
            continue
        if m.get('kind') in ('fraqtive', 'vlc'):
            ok = bool(m.get('ok'))
            keys = ('left_colours', 'left_nonblack', 'right_colours', 'right_nonblack', 'box', 'left', 'right', 'differ_outside')
        else:
            ok = (m.get('median_abs_px') is not None and m.get('differ_outside') == 0
                  and m.get('view_rect_is_widget', True) is not False)
            keys = ('median_abs_px', 'differ_outside', 'view_rect', 'view_rect_is_widget', 'error')
        out[s['step']] = (True, ok, json.dumps({k: m.get(k) for k in keys if k in m}))
    return out


def load(path):
    try:
        d = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) and 'case' in d else None


def main():
    rc = 0
    cases = {}
    for root in map(Path, sys.argv[1:]):
        for f in sorted(root.glob('**/*.json')):
            if f.parent.name.endswith('.measure') or f.name.startswith('step-'):
                continue
            d = load(f)
            if d:
                d['_folder'] = f.parent
                cases[d['case']] = d
    for name, d in sorted(cases.items()):
        if 'agree' in d:  # Qt's frame, frame-analyze.py
            bad = name.startswith('bad-')
            ok = (not d['agree']) if bad else d['agree']
            text = (f"disagreeing steps {d['disagreeing_steps']}" if d['disagreeing_steps'] else 'the frame and the content agree in every step') + f" ({len(d['steps'])} steps)"
            print(f"{'AS EXPECTED' if ok else 'NOT AS EXPECTED'}  {name}{' (known bad case)' if bad else ''}: {text}")
            rc |= not ok
    for name, d in sorted(cases.items()):
        if 'agree' in d or not name.startswith('bad-'):
            continue
        relag(d, d['_folder'])
        caught = placement(d)
        print(f"{'AS EXPECTED' if caught else 'NOT AS EXPECTED'}  {name} (known bad case): {'; '.join(caught) or 'NOT CAUGHT'}")
        rc |= not caught
    programs = sorted({n[:-4] for n in cases if n.endswith(('-pub', '-q24')) and 'agree' not in cases[n] and not n.startswith('bad-')})
    for p in programs:
        pub, q24 = cases.get(p + '-pub'), cases.get(p + '-q24')
        if not pub or not q24:
            print(f"NOT AS EXPECTED  {p}: a run is missing (published {bool(pub)}, +24 {bool(q24)})")
            rc = 1
            continue
        for d in (pub, q24):
            relag(d, d['_folder'])
        bad_pub, bad_q24 = placement(pub), placement(q24)

        def signature(bad):
            return sorted(b.split(' (runs')[0] if b.startswith('wire log') else b for b in
                          [('wire log: misplaced' if b.startswith('wire log:') else b.split(': ')[0] + ': ' + b.split(': ')[1].split(' ')[0])
                           for b in bad])
        same_placement = bool(bad_q24) and signature(bad_pub) == signature(bad_q24)
        m_pub, m_q24 = measure(pub), measure(q24)
        differs = [k for k in sorted(set(m_pub) | set(m_q24)) if (m_pub.get(k) or (0, None))[:2] != (m_q24.get(k) or (0, None))[:2]]
        findings = [f"step {k}: {m_q24[k][2]}" for k in sorted(m_q24) if m_q24[k][0] and not m_q24[k][1] and k not in differs]
        ok = (not bad_q24 or same_placement) and not differs
        lag = q24.get('lag') or {}
        line = (f"{p}: placement on +24 {'ok' if not bad_q24 else 'FAILS: ' + '; '.join(bad_q24)}"
                f" ({len(q24['steps'])} steps, {lag.get('commits')} commits read with {lag.get('offset_source')} offsets, "
                f"{lag.get('misplaced')} misplaced, {len(lag.get('frame_changes') or [])} placed with Qt's new frame: "
                f"{[{'buffer': c['buffer'], 'positions': c['positions']} for c in lag.get('frame_changes') or []]})"
                f"; published {'ok' if not bad_pub else 'FAILS: ' + '; '.join(bad_pub)}")
        if m_q24:
            line += "; the program's measure, +24: " + ', '.join(f"{k}: {v[2]}" for k, v in sorted(m_q24.items()))
        if differs:
            line += f"; the measure's verdict differs from the published run at steps {differs}"
        if same_placement:
            line += f"; FINDING on both Qts (the published set too): the placement fails the same way on +24 ({'; '.join(bad_q24)}) and published ({'; '.join(bad_pub)})"
        if findings:
            line += f"; FINDING on both Qts (the published set too): the program's measure fails at {findings}"
        diffs = [(s['step'], s.get('vs_control_left_px'), s.get('vs_control_right_px')) for s in q24['steps'] if 'vs_control_left_px' in s]
        line += f"; pixels of each eye differing from the published run per step: {diffs}"
        print(f"{'AS EXPECTED' if ok else 'NOT AS EXPECTED'}  {line}")
        rc |= not ok
    sys.exit(rc)


if __name__ == '__main__':
    main()
