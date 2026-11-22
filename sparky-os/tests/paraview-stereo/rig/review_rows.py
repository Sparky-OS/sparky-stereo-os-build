#!/usr/bin/env python3
"""review_rows.py PREFIX [ROW-SUBSTRING...]  -- lane 50f's review rows, run and judged by one command.

Every row runs in its own fresh container and Stereo KWin session (rig/run-case.sh) on the review images of
rig/make-review-images.sh, and writes under runs/PREFIX-ROW; the command refuses a PREFIX that already has runs, so an
earlier run is never overwritten. A build container of the lane is paused while the rows run (four CPUs). At the end a
table of row, expected and found goes to runs/PREFIX-table.txt and the terminal, and the exit status is 1 when any row is
not as expected (0 when all are). With ROW-SUBSTRINGs only the rows whose names contain one of them run.

Rows: continuation 2's (rig/c2-rows.sh: KScreen's page from three programs in two languages, the next start after Enable 3D
is switched off, an old screenshot stereo mode, the old-setting and old-state notices on both routes and both cards, two
translated notices, a flat view on Wayland with and without the colour-size rule), the 23 edition rows (rig/g3-batch.sh),
the red rows on Debian's packages, the two VTK reproducers, the mono views compared with Debian's, apt's upgrade plan on the
snapshot, and apt's dist-upgrade simulation of every review image (nothing held back on the snapshot).

The colour-size expectation follows the libvtk9.6 each image carries: Debian's 9.6.2+ds-3 and the edition's +stereo3d1 print
the warnings on a flat Wayland view, +stereo3d2 and later none.
"""
import json, os, re, subprocess, sys
from pathlib import Path

S = Path('/var/lib/sparky-lanes/science-paraview-50f')
L = '/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f'
ENV = dict(os.environ, DOCKER_HOST=f'unix://{L}/docker.sock')
R, PV, VT, I6, REF = 'sci50f-rig:1', 'sci50f-rig:green-pv2', 'sci50f-rig:green-vtk', 'sci50f-rig:green-i6b', 'sci50f-rig:pv2-ref'
EN, PT = 'LANG=en_US.UTF-8', 'LANG=pt_BR.UTF-8'
OFF = '{ "settings": { "GeneralSettings": { "AutoApply": 1 }, "RenderViewSettings": { "Enable3D": 0 } } }'
OLD = '{ "settings": { "GeneralSettings": { "AutoApply": 1 } }, "views": { "RenderView": { "StereoRender": 1, "StereoType": 7 } } }'
DOWN10 = 'Down Down Down Down Down Down Down Down Down Down Return'
STATE = 'PV_EXTRA=--state=/fixtures/anaglyph.pvsm'
XCB = 'QT_QPA_PLATFORM=xcb'

# (row, image, case, extra environment for run-case.sh (GPU, SESSION), case variables, kind)
ROWS = []
def row(name, image, case, kind, *vars, gpu='amd', session=None):
    ROWS.append((name, image, case, {'GPU': gpu, **({'SESSION': session} if session else {})}, list(vars), kind))

# the edition ParaView (rig/g3-batch.sh)
for i in (1, 2):
    row(f'pv-default-wl-amd-{i}', PV, 'pv-case.sh', 'pair', EN)
row('pv-default-wl-nv', PV, 'pv-case.sh', 'pair', EN, gpu='nvidia')
row('pv-default-x-amd', PV, 'pv-case.sh', 'pair', XCB, EN)
row('pv-default-x-nv', PV, 'pv-case.sh', 'pair', XCB, EN, gpu='nvidia')
row('pv-ce-wl-amd', PV, 'pv-case.sh', 'pair', 'PV_STEREO=Crystal Eyes', EN)
row('pv-off-wl-amd', PV, 'pv-case.sh', 'flat-wl', f'PV_SETTINGS={OFF}', EN)
row('pv-off-x-amd', PV, 'pv-case.sh', 'flat-x', f'PV_SETTINGS={OFF}', XCB, EN)
row('pv-off-wl-nv', PV, 'pv-case.sh', 'flat-wl', f'PV_SETTINGS={OFF}', EN, gpu='nvidia')
row('pv-off-x-nv', PV, 'pv-case.sh', 'flat-x', f'PV_SETTINGS={OFF}', XCB, EN, gpu='nvidia')
row('pv-menu-x-amd-en', PV, 'pv-case.sh', 'menu', 'MENU=1', XCB, EN)
row('pv-menu-x-amd-pt', PV, 'pv-case.sh', 'menu', 'MENU=1', XCB, PT)
row('pv-settings-en', PV, 'pv-settings-case.sh', 'settings', XCB, EN)
row('pv-settings-pt', PV, 'pv-settings-case.sh', 'settings', 'SEARCH=3D', XCB, PT)
row('pv-refuse-en', PV, 'pv-refuse-case.sh', 'refuse-en', EN)
row('pv-refuse-pt', PV, 'pv-refuse-case.sh', 'refuse-pt', PT)
row('pv-oldsetting-wl-amd-en', PV, 'pv-case.sh', 'pair+notice-en', f'PV_SETTINGS={OLD}', EN)
row('pv-oldsetting-wl-amd-pt', PV, 'pv-case.sh', 'pair+notice-pt', f'PV_SETTINGS={OLD}', PT)
row('pv-oldstate-wl-amd', PV, 'pv-case.sh', 'pair+notice-en', 'PV_NODATA=1', STATE, EN)
row('pv-oldstate-off-wl-amd', PV, 'pv-case.sh', 'flat-wl+notice-en', 'PV_NODATA=1', STATE, f'PV_SETTINGS={OFF}', EN)
row('pv-oldstate-wl-amd-pt', PV, 'pv-case.sh', 'pair+notice-pt', 'PV_NODATA=1', STATE, PT)
row('pv-noareas-en', PV, 'none', 'noareas-en', EN, session='pv-noareas-case.sh')
row('pv-noareas-pt', PV, 'none', 'noareas-pt', PT, session='pv-noareas-case.sh')
# continuation 2's rows (rig/c2-rows.sh)
row('c2-display-pv-en', PV, 'pv-case.sh', 'display-en', 'MENU=1', 'MENU_KEYS=Up Return', XCB, EN)
row('c2-display-pv-pt', PV, 'pv-case.sh', 'display-pt', 'MENU=1', 'MENU_KEYS=Up Return', XCB, PT)
row('c2-display-jmol-en', I6, 'jmol-menu-case.sh', 'display-en', 'MENU_X=150', 'MENU_Y=11', 'MENU_KEY=alt+d', 'MENU_WAIT=4',
    f'ACT_KEYS={DOWN10}', EN)
row('c2-display-jmol-pt', I6, 'jmol-menu-case.sh', 'display-pt', 'MENU_X=150', 'MENU_Y=11', 'MENU_KEY=alt+a', 'MENU_KEY2=Right Right',
    'MENU_WAIT=4', f'ACT_KEYS=Down {DOWN10}', PT, 'LC_ALL=pt_BR.UTF-8')
row('c2-display-mpl-en', I6, 'mpl-case.sh', 'display-en', 'MPLBACKEND=TkAgg', 'ACT=display', EN)
row('c2-display-mpl-pt', I6, 'mpl-case.sh', 'display-pt', 'MPLBACKEND=TkAgg', 'ACT=display', PT, 'LC_ALL=pt_BR.UTF-8')
row('c2-restart-x-amd', PV, 'pv-restart-case.sh', 'restart', XCB, EN)
row('c2-shot-wl-amd', PV, 'pv-shot-case.sh', 'shot', EN)
row('c2-oldsetting-x-amd', PV, 'pv-case.sh', 'pair+notice-en', f'PV_SETTINGS={OLD}', XCB, EN)
row('c2-oldsetting-wl-nv', PV, 'pv-case.sh', 'pair+notice-en', f'PV_SETTINGS={OLD}', EN, gpu='nvidia')
row('c2-oldsetting-x-nv', PV, 'pv-case.sh', 'pair+notice-en', f'PV_SETTINGS={OLD}', XCB, EN, gpu='nvidia')
row('c2-oldstate-x-amd', PV, 'pv-case.sh', 'pair+notice-en', 'PV_NODATA=1', STATE, XCB, EN)
row('c2-oldstate-wl-nv', PV, 'pv-case.sh', 'pair+notice-en', 'PV_NODATA=1', STATE, EN, gpu='nvidia')
row('c2-oldstate-x-nv', PV, 'pv-case.sh', 'pair+notice-en', 'PV_NODATA=1', STATE, XCB, EN, gpu='nvidia')
row('c2-oldsetting-wl-amd-de', PV, 'pv-case.sh', 'pair+notice-de', f'PV_SETTINGS={OLD}', 'LANG=de_DE.UTF-8', 'LC_ALL=de_DE.UTF-8')
row('c2-noareas-ja', PV, 'none', 'noareas-ja', 'LANG=ja_JP.UTF-8', 'LC_ALL=ja_JP.UTF-8', session='pv-noareas-case.sh')
row('c2-off-wl-amd-shimfix', PV, 'pv-case.sh', 'flat-wl-fixed', f'PV_SETTINGS={OFF}', 'LD_PRELOAD=/rig/libcolour-size-shim.so',
    'COLOUR_SIZE_SHIM=fix', EN)
row('c2-jm-pair', I6, 'jmol-case.sh', 'jmol-pair', EN)
row('c2-mpl-tk-pair', I6, 'mpl-case.sh', 'mpl-pair', 'MPLBACKEND=TkAgg', EN)
# Debian's packages (the red rows) and Debian's mono picture for the comparison
row('red-ce-wl-amd', R, 'pv-case.sh', 'red-pair', 'PV_STEREO=Crystal Eyes', EN)
row('red-ce-x-nv', R, 'pv-case.sh', 'red-pair', 'PV_STEREO=Crystal Eyes', XCB, EN, gpu='nvidia')
row('red-mono-wl-amd', R, 'pv-case.sh', 'flat-wl', EN)
row('red-mono-x-amd', R, 'pv-case.sh', 'flat-x', XCB, EN)
row('red-oldstate-wl-amd', R, 'pv-case.sh', 'red-anaglyph', 'PV_NODATA=1', STATE, EN)
# paraview +stereo3d2 on the vtk9 kept in ref/ (the previous edition build): a flat view on Wayland, both cards; the image
# exists only when ref/ holds a vtk9 folder, and its rows are reported as skipped otherwise
row('ref-off-wl-amd', REF, 'pv-case.sh', 'flat-wl', f'PV_SETTINGS={OFF}', EN)
row('ref-off-wl-nv', REF, 'pv-case.sh', 'flat-wl', f'PV_SETTINGS={OFF}', EN, gpu='nvidia')
row('ref-cs-wl-amd', REF, 'cs-case.sh', 'cs-wl')
# the VTK reproducers: the draw-buffer one (Crystal Eyes) and the colour-size one (a flat native widget)
row('qb-red-wl-amd', R, 'qb-case.sh', 'qb-red')
for route, rv in (('wl', []), ('x', [XCB])):
    for gpu, g in (('amd', 'amd'), ('nv', 'nvidia')):
        row(f'qb-{route}-{gpu}', VT, 'qb-case.sh', 'qb-green', *rv, gpu=g)
        row(f'cs-red-{route}-{gpu}', R, 'cs-case.sh', f'cs-{route}', *rv, gpu=g)
        row(f'cs-vtk-{route}-{gpu}', VT, 'cs-case.sh', f'cs-{route}', *rv, gpu=g)
row('cs-shimfix-wl-amd', R, 'cs-case.sh', 'cs-fixed', 'SHIM=fix')


def text(p):
    try:
        return Path(p).read_text(errors='replace')
    except OSError:
        return ''


def analyze(script, d):
    r = subprocess.run([sys.executable, '-I', str(S / 'rig' / script), str(d)], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {}


def declared(d):
    if re.search(r'set_content', text(d / 'wl.txt')):
        return True
    try:
        return any(k.startswith('_KDE_NET_WM_STEREO_CONTENT') for w in json.loads(text(d / 'props.json'))['windows'] for k in w['props'])
    except (ValueError, KeyError, TypeError):
        return False


def colour(d):
    return len(re.findall(r'Failed to get (?:red|green|blue|alpha) color buffer size', text(d / 'paraview.log')))


def messages(d):
    return 'WIN|Output Messages' in text(d / 'windows.txt')


def drawbuf(d):
    return len(re.findall(r'Error in cache state for GL_DRAW_BUFFER', text(d / 'paraview.log')))


def info_lines(d, src, f='paraview.log'):
    return [l for l in text(d / f).splitlines() if src in l and 'INFO|' in l]


def pixels_differ(a, b):
    from PIL import Image, ImageChops
    try:
        A, B = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    except OSError:
        return -1
    if A.size != B.size:
        return A.size[0] * A.size[1]
    return sum(1 for p in ImageChops.difference(A, B).getdata() if p != (0, 0, 0))


def judge(name, kind, d, colour_expected):
    """returns (expected, found, ok)"""
    pv = lambda: analyze('pv_analyze.py', d)
    if kind.startswith('pair'):
        a = pv(); m = a.get('measured', {}); v = a.get('disparity', {})
        vert = (v.get('near_red', {}).get('y0'), v.get('far_blue', {}).get('y0'))
        found = (f"stereo={a.get('stereo')} near={m.get('near')} far={m.get('far')} vertical={vert} declared={declared(d)} "
                 f"drawbuffer={drawbuf(d)} colour={colour(d)} OutputMessages={messages(d)}")
        ok = (a.get('stereo') is True and declared(d) and drawbuf(d) == 0 and colour(d) == 0 and not messages(d))
        if '+notice' not in kind:
            ok = ok and m.get('near') == -5.0 and m.get('far') == 4.0 and vert == (0, 0)
            exp = 'pair near -5 far +4 vertical 0, declared, 0 draw-buffer and 0 colour warnings, no Output Messages'
        else:  # the old setting or state changes the view's picture: the pair, the declaration and the notice are judged
            exp = 'a declared pair, 0 draw-buffer and 0 colour warnings, no Output Messages'
        if '+notice' in kind:
            ok2, f2, e2 = notice(d, kind.split('+notice-')[1]); ok, found, exp = ok and ok2, found + '; ' + f2, exp + '; ' + e2
        return exp, found, ok
    if kind.startswith('flat-wl') or kind == 'flat-x':
        a = pv(); c = colour(d)
        want = 0 if (kind == 'flat-x' or kind == 'flat-wl-fixed') else colour_expected
        found = f"stereo={a.get('stereo')} declared={declared(d)} colour={c} OutputMessages={messages(d)}"
        ok = a.get('stereo') is False and not declared(d) and ((c > 0) == (want > 0)) and messages(d) == (c > 0)
        exp = f"flat, nothing declared, {'colour warnings and Output Messages' if want else '0 colour warnings, no Output Messages'}"
        if '+notice' in kind:
            ok2, f2, e2 = notice(d, kind.split('+notice-')[1]); ok, found, exp = ok and ok2, found + '; ' + f2, exp + '; ' + e2
        return exp, found, ok
    if kind == 'red-pair':
        a = pv(); n = drawbuf(d)
        return ('Debian: a pair with GL_DRAW_BUFFER warnings and Output Messages', f"stereo={a.get('stereo')} drawbuffer={n} "
                f"OutputMessages={messages(d)}", a.get('stereo') is True and n > 0 and messages(d))
    if kind == 'red-anaglyph':
        a = pv()
        return ('Debian: the state file draws its anaglyph into one picture, nothing declared',
                f"stereo={a.get('stereo')} declared={declared(d)}", a.get('stereo') is False and not declared(d))
    if kind == 'menu':
        n = pixels_differ(d / 'shot2.png', d / 'shot-menu.png')
        return 'the View menu drawn over the window (capture differs)', f'{n} pixels differ', n > 2000
    if kind == 'settings':
        n = pixels_differ(d / 'shot-main.png', d / 'shot-settings-1.png')
        return 'the Settings dialog drawn on its Render View tab (capture differs)', f'{n} pixels differ', n > 20000
    if kind.startswith('refuse'):
        lang = kind.split('-')[1]; want = {'en': 'is not offered', 'pt': 'não é oferecido'}[lang]; bad = []
        for t in ('SplitViewportHorizontal', 'Red-Blue', 'Interlaced', 'Anaglyph', 'Checkerboard', 'Dresden'):
            f = text(d / f'refuse-{t}.txt')
            if 'rc=1' not in f or want not in f:
                bad.append(t)
        ce = text(d / 'refuse-Crystal_Eyes.txt'); ce_ok = 'rc=143' in ce or 'still running' in ce
        return (f'six types exit 1 with "{want}"; Crystal Eyes starts', f"refused wrongly: {bad or 'none'}; Crystal Eyes started={ce_ok}",
                not bad and ce_ok)
    if kind.startswith('noareas'):
        lang = kind.split('-')[1]; lines = info_lines(d, 'pqQVTKWidget.cxx')
        want = {'en': 'These 3D views are shown flat', 'pt': None, 'ja': 'このデスクトップは'}[lang]
        good = [l for l in lines if (want in l if want else ('These 3D views' not in l and '3D' in l))]
        win = text(d / 'paraview-windows.txt').strip()
        return (f'told once ({lang}) in the log, a notice window', f'{len(good)} line(s), ParaView windows {win}',
                len(good) == 1 and len(lines) == 1 and win.isdigit() and int(win) >= 2)
    if kind.startswith('display'):
        lang = kind.split('-')[1]; w = text(d / 'windows-act.txt')
        cap = {'en': 'Display Configuration', 'pt': 'Configurações da tela'}[lang]
        return f'KScreen\'s page opens: "{cap}", kcm_kscreen', w.replace('\n', ' ')[:160], f'WIN|{cap}|' in w and '|kcm_kscreen|' in w
    if kind == 'restart':
        f, s = d / 'first', d / 'second'; a2 = analyze('pv_analyze.py', s)
        q = text(f / 'quit.txt').strip(); e3 = '"Enable3D" : 0' in text(f / 'settings-after-quit.json')
        found = f'first declared={declared(f)}, quit "{q}", saved Enable3D 0={e3}; second stereo={a2.get("stereo")} declared={declared(s)}'
        return ('first start a declared pair, ParaView exits by itself, Enable3D 0 saved, second start flat',
                found, declared(f) and q == 'exited by itself' and e3 and a2.get('stereo') is False and not declared(s))
    if kind == 'shot':
        p = text(d / 'pvpython.log'); rc = text(d / 'rc.txt').strip()
        want = ['int-7 saved', 'both-eyes saved', 'string-anaglyph failed', 'is not offered']
        miss = [w for w in want if w not in p]
        return 'pvpython: int 7 saved with the sentence, both eyes saved, the old string refused', f'{rc}, missing: {miss or "none"}', not miss and rc == 'rc=0'
    if kind == 'jmol-pair':
        a = analyze('jmol_analyze.py', d); atoms = a.get('atoms', {})
        bad = [k for k, v in atoms.items() if abs(v['measured'] - v['predicted']) > 1 or v['vertical'] != 0]
        return ('a declared pair, every atom within 1 px of the prediction, vertical 0', f"stereo={a.get('stereo')} declared="
                f"{len(a.get('declared', []))} atoms={len(atoms)} off={bad} outside={a.get('differing_outside')}",
                a.get('stereo') is True and a.get('declared') and atoms and not bad and a.get('differing_outside') == 0)
    if kind == 'mpl-pair':
        a = analyze('mpl_analyze.py', d); mk = a.get('markers', {})
        bad = [k for k, v in mk.items() if abs(v['measured'] - v['predicted']) > 0.5 or abs(v['vertical']) > 0.5]
        return ('a declared pair, every marker within 0.5 px of the prediction', f"stereo={a.get('stereo')} markers={len(mk)} off={bad} "
                f"outside={a.get('differing_outside')}", a.get('stereo') is True and mk and not bad and a.get('differing_outside') == 0)
    if kind.startswith('qb'):
        out, rc = text(d / 'qb.out'), text(d / 'rc.txt').strip()
        m = re.search(r'GL_DRAW_BUFFER warnings: (\d+)', out); n = int(m.group(1)) if m else -1
        ctx = 'stereo context: yes' in out
        if kind == 'qb-red':
            return 'Debian: warnings in 60 frames, exit 1', f'{rc} warnings={n} stereo={ctx}', rc == 'rc=1' and n > 0 and ctx
        return 'no GL_DRAW_BUFFER warning in 60 frames, exit 0', f'{rc} warnings={n} stereo={ctx}', rc == 'rc=0' and n == 0 and ctx
    if kind.startswith('cs'):
        out, rc = text(d / 'cs.out'), text(d / 'rc.txt').strip()
        m = re.search(r'color buffer size warnings: (\d+)', out); n = int(m.group(1)) if m else -1
        want = 0 if kind in ('cs-x', 'cs-fixed') else colour_expected
        return (f"{'colour warnings, exit 1' if want else '0 colour warnings, exit 0'}", f'{rc} warnings={n}',
                (n > 0 and rc == 'rc=1') if want else (n == 0 and rc == 'rc=0'))
    return 'unknown kind', kind, False


def notice(d, lang):
    lines = info_lines(d, 'pqRenderView.cxx')
    want = {'en': 'A saved setting or state file asked for "Anaglyph"', 'de': 'Eine gespeicherte Einstellung', 'pt': None}[lang]
    good = [l for l in lines if (want in l if want else ('Anaglyph' in l and 'A saved setting' not in l))]
    return len(good) >= 1, f'notice lines {len(good)}', f'the old-type notice ({lang})'


def vtk_version(image):
    r = subprocess.run([str(S / 'scripts/drun.sh'), 'vtkver', image, '--network', 'none', '--', 'dpkg-query', '-W', '-f',
                        '${Version}', 'libvtk9.6'], capture_output=True, text=True, env=ENV)
    return r.stdout.strip()


def main():
    prefix = sys.argv[1]
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,30}', prefix):
        sys.exit('PREFIX: lower-case letters, digits and dashes')
    only = sys.argv[2:]
    runs = S / 'runs'
    if any(runs.glob(f'{prefix}-*')):
        sys.exit(f'runs/{prefix}-* exist: choose another PREFIX (earlier runs are never overwritten)')
    images = {}
    for im in (R, VT, PV, I6, REF):
        images[im] = vtk_version(im)
    missing = [im for im in (R, VT, PV, I6) if not images[im]]
    if missing:
        sys.exit(f'images missing: {missing}: make them first with rig/make-review-images.sh')
    colour_for = {im: (0 if re.search(r'\+stereo3d([2-9]|\d\d)', v) else 1) for im, v in images.items()}
    lines = [f'{im} libvtk9.6 {v or "(none: image missing)"}' for im, v in images.items()]
    paused = subprocess.run(['docker', 'ps', '-q', '--filter', 'name=sci50f-build-'], capture_output=True, text=True, env=ENV).stdout.split()
    for c in paused:
        subprocess.run(['docker', 'pause', c], env=ENV, capture_output=True)
    table = []
    try:
        for name, image, case, extra, vars, kind in ROWS:
            if only and not any(o in name for o in only):
                continue
            rn = f'{prefix}-{name}'
            if not images.get(image):
                table.append((rn, image.split(':')[1], 'skipped', f'not run: no image {image}', None))
                print('SKIP ' + rn, flush=True)
                continue
            subprocess.run([str(S / 'rig/run-case.sh'), rn, image, case, *vars], env={**ENV, **extra}, capture_output=True)
            exp, found, ok = judge(name, kind, runs / rn, colour_for.get(image, 1))
            table.append((rn, image.split(':')[1], exp, found, ok))
            print(('PASS ' if ok else 'FAIL ') + rn + ' | ' + found, flush=True)
        # Enable 3D off equals Debian's mono picture (the render view, pixel for pixel)
        for a, b in (('pv-off-wl-amd', 'red-mono-wl-amd'), ('pv-off-x-amd', 'red-mono-x-amd')):
            if (runs / f'{prefix}-{a}').is_dir() and (runs / f'{prefix}-{b}').is_dir():
                r = subprocess.run([sys.executable, '-I', str(S / 'rig/view_equal.py'), str(runs / f'{prefix}-{a}'), str(runs / f'{prefix}-{b}')],
                                   capture_output=True, text=True)
                try:
                    v = json.loads(r.stdout); found, ok = f"{v['differing']} of {v['pixels']} pixels differ", v['differing'] == 0
                except (ValueError, KeyError):
                    found, ok = r.stdout.strip()[:120] or r.stderr.strip()[:120], False
                table.append((f'{prefix}-equal-{a}', 'pv2/1', "the render view equals Debian's mono start", found, ok))
    finally:
        for c in paused:
            subprocess.run(['docker', 'unpause', c], env=ENV, capture_output=True)
    if not only or any(o in 'apt' for o in only):
        # apt's upgrade plan on the snapshot: Debian's ten packages to the stage's, on the rig without a desktop (KScreen's
        # page and its dependencies come new) and on an image that already has KScreen (green-i6b: nothing else changes)
        TEN = {'libvtk9.6', 'libvtk9.6-qt', 'libvtk9-dev', 'libvtk9-qt-dev', 'python3-vtk9', 'libvtk9-java', 'vtk9', 'paraview',
               'paraview-dev', 'python3-paraview'}
        for img, tag, new_ok in ((R, 'plan-without-desktop', True), (I6, 'plan-with-kscreen', False)):
            subprocess.run([str(S / 'rig/apt-upgrade-sim.sh')], env={**ENV, 'OUT': f'{prefix}-{tag}-', 'IMG': img}, capture_output=True, text=True)
            sim = text(runs / f'{prefix}-{tag}-apt-upgrade-sim.txt')
            ups = re.findall(r'^Inst (\S+) \[[^\]]+\] \((\S+)', sim, re.M)
            remv = re.findall(r'^Remv ', sim, re.M)
            m = re.search(r'(\d+) upgraded, (\d+) newly installed, (\d+) to remove and (\d+) not upgraded', sim)
            ok = (bool(m) and {n for n, _ in ups} == TEN and all('+stereo3d' in v for _, v in ups) and not remv
                  and m.group(3) == '0' and m.group(4) == '0' and (new_ok or m.group(2) == '0'))
            exp = ("the ten Debian packages upgraded to the stage, nothing removed or kept back"
                   + ("" if new_ok else ", nothing new"))
            table.append((f'{prefix}-apt-{tag}', img.split(':')[1], exp,
                          (m.group(0) if m else sim.strip()[-120:]) + f'; upgraded to the stage: {len(ups)}', bool(ok)))
        # every review image resolves on the snapshot with nothing to upgrade and nothing held
        for im in (R, VT, PV, I6):
            tag = im.split(':')[1]
            r = subprocess.run([str(S / 'scripts/drun.sh'), f'du-{tag}', im, '--cpus', '1', '-v', '/var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro',
                                '-v', f'{S}/frozen/dmo:/dmo:ro', '-v', f'{S}/keys:/run/keys:ro', '--user', '0:0', '--', 'sh', '-c',
                                'sh /run/https-only-apt.sh >/dev/null; rm -f /etc/apt/sources.list.d/stage.list; apt-get update -qq 2>&1 | tail -3; '
                                'echo "snapshot $(cat /etc/apt/sci50f-snapshot)"; apt-get -s dist-upgrade | grep -E "^(Inst|Remv)|upgraded"'],
                               capture_output=True, text=True, env=ENV)
            (runs / f'{prefix}-dist-upgrade-{tag}.txt').write_text(r.stdout + r.stderr)
            m = re.search(r'(\d+) upgraded, (\d+) newly installed, (?:(\d+) downgraded, )?(\d+) to remove and (\d+) not upgraded', r.stdout)
            snap = re.search(r'snapshot (\S+)', r.stdout)
            table.append((f'{prefix}-dist-upgrade-{tag}', tag, 'on the snapshot: 0 upgraded, 0 new, 0 downgraded, 0 to remove, 0 not upgraded',
                          f"{snap.group(1) if snap else '?'}: {m.group(0) if m else r.stdout.strip()[-120:]}",
                          bool(m) and m.group(1) == m.group(2) == m.group(4) == m.group(5) == '0' and m.group(3) in (None, '0')))
    out = [f'review rows {prefix}', *lines, '', f'{"row":<44} {"image":<10} {"result":<5} expected | found']
    for rn, im, exp, found, ok in table:
        out.append(f'{rn:<44} {im:<10} {"SKIP" if ok is None else "PASS" if ok else "FAIL":<5} {exp} | {found}')
    bad = sum(1 for t in table if t[4] is False); skipped = sum(1 for t in table if t[4] is None)
    out.append(f'\n{len(table)} rows, {len(table) - bad - skipped} as expected, {bad} not, {skipped} skipped (image absent)')
    (runs / f'{prefix}-table.txt').write_text('\n'.join(out) + '\n')
    print('\n'.join(out))
    sys.exit(1 if bad or len(table) == skipped else 0)


if __name__ == '__main__':
    main()
