# SPDX-License-Identifier: GPL-2.0-or-later
"""ORDER 146e: a saver the catalogue cannot offer is named with its reason; the receipts' packages are pinned;
the publication gate refuses a round whose catalogue would drop savers. Needs no installed XScreenSaver: it
builds a small repository of its own (each failing case is shown red, then the matching case green).
Run from the gl-stereo folder: python3 tests/saver-receipts.py   (xvfb-run for the dialog part)"""
import hashlib
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

here = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(here/'savers'))
import catalogue
import pin
import settings

def sha(data):
    return hashlib.sha256(data).hexdigest()

def load_gate():
    spec = importlib.util.spec_from_file_location('gate', here/'packaging/check-round-savers.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

gate = load_gate()

# ---- a deb writer (ar, control.tar.xz, data.tar.xz) -------------------------------------------------------
def tar_bytes(files):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w') as tar:
        for name, data in files.items():
            info = tarfile.TarInfo('./' + name.lstrip('/')); info.size = len(data); info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))
    return lzma.compress(out.getvalue())

def write_deb(folder, name, version, files, depends='', source=None):
    control = 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: t <t@example.org>\nDescription: t\n' % (name, version)
    if depends: control += 'Depends: %s\n' % depends
    if source: control += 'Source: %s\n' % source
    members = [('debian-binary', b'2.0\n'), ('control.tar.xz', tar_bytes({'control': control.encode()})), ('data.tar.xz', tar_bytes(files))]
    blob = b'!<arch>\n'
    for member, data in members:
        blob += (member + '/').ljust(16).encode() + b'0'.ljust(12) + b'0'.ljust(6) + b'0'.ljust(6) + b'100644'.ljust(8) + str(len(data)).ljust(10).encode() + b'`\n' + data + (b'\n' if len(data) & 1 else b'')
    Path(folder, '%s_%s_amd64.deb' % (name, version)).write_bytes(blob)

def receipt(name, executable, layer, settings_data):
    return dict(id=name, command=['/usr/libexec/xscreensaver/' + name], environment={}, library='/usr/lib/gl-stereo/libgl-stereo.so',
                executable_sha256=sha(executable), library_sha256=sha(layer),
                proof=dict(passed=True, oracle='depth-v1', residual_px=0.0, disparity_bounds_px=[1.0, 2.0], eye_width=640, placement='screen-level'),
                qualification=dict(state='qualified', group='layer'),
                verification=dict(settings_sha256=sha(settings_data)))

def round_of(folder, xs_version, saver_depends, tamper=None):
    """A round: gl-stereo (layer), gl-stereo-savers (3 receipts) and xscreensaver-gl at XS_VERSION."""
    folder.mkdir(parents=True)
    layer = b'layer-binary'
    executables = {name: b'saver ' + name.encode() + b' ' + xs_version.encode() for name in ('gears', 'glplanet', 'pipes')}
    qualified = {name: b'saver ' + name.encode() + b' 6.09-2+stereo3d4' for name in executables}
    xml = b'<screensaver/>'
    entries = [receipt(name, qualified[name], layer, xml) for name in executables]
    inventory = [dict(id=name, kind='hack', title=name) for name in executables]
    if tamper: tamper(entries)
    write_deb(folder, 'gl-stereo', '0.4.4-1', {'usr/lib/gl-stereo/libgl-stereo.so': layer})
    write_deb(folder, 'gl-stereo-savers', '0.4.4-1', {'usr/share/gl-stereo/catalogue.json': json.dumps(entries).encode(),
                                                      'usr/share/gl-stereo/savers.json': json.dumps(inventory).encode()}, depends=saver_depends)
    files = {'usr/libexec/xscreensaver/' + name: data for name, data in executables.items()}
    files.update({'usr/share/xscreensaver/config/%s.xml' % name: xml for name in executables})
    write_deb(folder, 'xscreensaver-gl', xs_version, files, source='xscreensaver')

def run_gate(folder):
    done = subprocess.run([sys.executable, str(here/'packaging/check-round-savers.py'), '--debs', str(folder)], capture_output=True, text=True)
    return done.returncode, done.stdout

with tempfile.TemporaryDirectory(prefix='saver-receipts-') as work:
    work = Path(work)
    # ---- the gate: red, then green ------------------------------------------------------------------------
    # RED 1: the XScreenSaver build differs from the one the receipts name (0.4.2 against +stereo3d4: 1 of 132)
    round_of(work/'red-build', '6.09-2+stereo3d5', 'gl-stereo (= 0.4.4-1), xscreensaver-gl (= 6.09-2+stereo3d5)')
    code, out = run_gate(work/'red-build')
    assert code == 1 and 'GATE REFUSES THE ROUND' in out, out
    assert '0 of 3 savers can be offered' in out, out
    want = '/usr/libexec/xscreensaver/gears differs: qualified %s, installed %s' % (sha(b'saver gears 6.09-2+stereo3d4'), sha(b'saver gears 6.09-2+stereo3d5'))
    assert want in out, out
    # RED 2: the build matches but Depends is not the exact version
    round_of(work/'red-pin', '6.09-2+stereo3d4', 'gl-stereo (= 0.4.4-1), xscreensaver-gl (>= 6.09-2+stereo3d3)')
    code, out = run_gate(work/'red-pin')
    assert code == 1 and '3 of 3 savers can be offered' in out and 'not an exact version' in out, out
    # RED 3: one saver's receipt names a settings file that differs
    def settings_changed(entries): entries[1]['verification']['settings_sha256'] = '0' * 64
    round_of(work/'red-settings', '6.09-2+stereo3d4', 'xscreensaver-gl (= 6.09-2+stereo3d4)', settings_changed)
    code, out = run_gate(work/'red-settings')
    assert code == 1 and '2 of 3 savers can be offered' in out and 'REFUSED glplanet: settings file' in out, out
    # RED 4: the XScreenSaver package is not in the round: the gate cannot look, so it refuses too
    (work/'red-missing').mkdir()
    for deb in (work/'red-pin').glob('gl-stereo*.deb'): (work/'red-missing'/deb.name).symlink_to(deb)
    code, out = run_gate(work/'red-missing')
    assert code == 2 and 'gate cannot run' in out, (code, out)
    # GREEN: the matching build, pinned exactly
    round_of(work/'green', '6.09-2+stereo3d4', 'gl-stereo (= 0.4.4-1), xscreensaver-gl (= 6.09-2+stereo3d4)')
    code, out = run_gate(work/'green')
    assert code == 0 and '3 of 3 savers can be offered' in out and 'GATE PASSES' in out, out
    print('PASS: the gate refuses a build that differs, an unpinned Depends, a changed settings file and a missing package; passes the pinned match')

    # ---- the catalogue code: reasons name the file and both hashes ---------------------------------------
    root = work/'green-root'
    for deb in sorted((work/'green').glob('*.deb')): gate.deb_extract(deb, root)
    entries = json.loads((root/'usr/share/gl-stereo/catalogue.json').read_text())
    assert catalogue.dropped(entries, str(root)) == []
    root_bad = work/'red-root'
    for deb in sorted((work/'red-build').glob('*.deb')): gate.deb_extract(deb, root_bad)
    gone = catalogue.dropped(entries, str(root_bad))
    assert [name for name, _ in gone] == ['gears', 'glplanet', 'pipes']
    reason = gone[0][1][0]
    assert reason['kind'] == 'executable-differs' and reason['expected'] == entries[0]['executable_sha256'] and reason['found'] == sha(b'saver gears 6.09-2+stereo3d5')
    done = subprocess.run([sys.executable, str(here/'savers/catalogue.py'), str(root/'usr/share/gl-stereo/catalogue.json'), str(root_bad)], capture_output=True, text=True)
    assert done.returncode == 1 and 'gears is not offered: executable /usr/libexec/xscreensaver/gears differs' in done.stdout and '0 of 3' in done.stdout, done.stdout
    # a missing executable and a missing layer are said, not skipped
    nothing = work/'empty-root'; nothing.mkdir()
    kinds = {r['kind'] for _, reasons in catalogue.dropped(entries, str(nothing)) for r in reasons}
    assert kinds == {'executable-missing', 'library-missing', 'settings-missing'}, kinds
    # eligible() keeps its old meaning on a receipt that cannot be read
    assert not catalogue.eligible({'id': 'x'}) and catalogue.diagnose({'id': 'x'})[0]['kind'] == 'proof'
    print('PASS: every dropped saver is named with the differing file and both hashes; missing files are said')

    # ---- the pin: generated from what owns the bound files -----------------------------------------------
    owners = {'/usr/libexec/xscreensaver/gears': ['xscreensaver-gl'], '/usr/share/xscreensaver/config/gears.xml': ['xscreensaver-data'],
              '/usr/libexec/xscreensaver/glplanet': ['xscreensaver-gl-extra'], '/usr/share/xscreensaver/config/glplanet.xml': ['xscreensaver-data']}
    versions = {'xscreensaver-gl': '6.09-2+stereo3d4', 'xscreensaver-gl-extra': '6.09-2+stereo3d4', 'xscreensaver-data': '6.09-2+stereo3d4'}
    found = pin.pins(entries[:2], find_owner=owners.get, find_version=versions.get)
    assert found == versions, found
    assert pin.substvar(found) == 'receipts:Pin=xscreensaver-data (= 6.09-2+stereo3d4), xscreensaver-gl (= 6.09-2+stereo3d4), xscreensaver-gl-extra (= 6.09-2+stereo3d4)'
    try:
        pin.pins(entries[:1], find_owner=lambda path: None, find_version=versions.get)
        raise AssertionError('an unowned bound file must stop the build')
    except SystemExit as stop:
        assert 'no installed package owns' in str(stop)
    print('PASS: the Depends pin is generated from the packages that own the bound files, and an unowned file stops the build')

    # ---- the saver list: the dropped savers, the reason, nine languages -------------------------------------
    strings = json.loads((here/'savers/strings.json').read_text())
    assert set(strings) == {'en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW'}
    import re
    for language, text in strings.items():
        assert len(text) == 18 and all(text), language
        for index in range(12, 16):
            assert re.findall(r'%[.\d]*s', text[index]) == re.findall(r'%[.\d]*s', strings['en'][index]), (language, index)
        assert text[11] % dict(dropped=2, shipped=132), language
    sample = dict(kind='executable-differs', path='/usr/libexec/xscreensaver/gears', expected='a' * 64, found='b' * 64)
    for language, text in strings.items():
        said = settings.reason_text(sample, text)
        assert '/usr/libexec/xscreensaver/gears' in said and 'a' * 12 in said and 'b' * 12 in said and 'a' * 13 not in said, (language, said)
    if os.environ.get('DISPLAY'):
        import tkinter as tk
        from tkinter import ttk
        share = work/'share'; share.mkdir()
        (share/'catalogue.json').write_text((root/'usr/share/gl-stereo/catalogue.json').read_text())
        inventory = json.loads((root/'usr/share/gl-stereo/savers.json').read_text()) + [dict(id='nodata', kind='hack', title='Nodata')]
        (share/'savers.json').write_text(json.dumps(inventory))
        # the catalogue's three receipts name files that are not on this machine: all three dropped, the fourth has no receipt
        os.environ.update(LC_ALL='de_DE.UTF-8', XDG_CONFIG_HOME=str(work/'config'))
        original, results = tk.Tk, []
        def create():
            window = original()
            def verify():
                try:
                    def walk(parent):
                        for child in parent.winfo_children():
                            yield child; yield from walk(child)
                    widgets = list(walk(window))
                    tree = next(w for w in widgets if isinstance(w, ttk.Treeview))
                    texts = [w.cget('text') for w in widgets if 'text' in w.keys()]
                    results.append((tree.item('gears', 'values'), tree.item('nodata', 'values'), texts))
                except Exception as error:
                    results.append(error)
                window.destroy()
            window.after(300, verify)
            return window
        tk.Tk = create
        settings.main(share)
        tk.Tk = original
        assert results and not isinstance(results[0], Exception), results
        gears, nodata, texts = results[0]
        assert gears[0] == strings['de'][9] and '/usr/libexec/xscreensaver/gears' in gears[2], gears
        assert nodata[0] == strings['de'][6] and nodata[2] == '', nodata
        assert strings['de'][11] % dict(dropped=3, shipped=4) in texts, texts
        print('PASS: the saver list says "%s" with the reason and a count for each saver the package cannot offer (de), and keeps "pending" for one with no receipt' % strings['de'][9])
    else:
        print('SKIP: no DISPLAY, the dialog part needs xvfb-run')
print('PASS: saver receipts, pin, gate and the list of savers that cannot be offered')
