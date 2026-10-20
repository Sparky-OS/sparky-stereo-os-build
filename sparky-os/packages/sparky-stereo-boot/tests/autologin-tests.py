#!/usr/bin/python3
# Tests of the autologin rule: which person the display manager logs in automatically, read
# the way Plasma Login Manager (/etc/plasmalogin.conf) and SDDM (sddm.conf.d, then sddm.conf,
# the later file winning) read it.   autologin-tests.py PATH/TO/sparky-stereo-boot
import importlib.machinery, importlib.util, os, shutil, sys, tempfile
TOOL = os.path.abspath(sys.argv[1])
results = []
def load(root):
    os.environ['SPARKY_STEREO_ROOT'] = root
    loader = importlib.machinery.SourceFileLoader('ssb', TOOL)
    spec = importlib.util.spec_from_loader('ssb', loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m
def case(name, dm, files, expect):
    root = tempfile.mkdtemp()
    try:
        if dm:
            os.makedirs(root + '/etc/systemd/system')
            os.symlink('/usr/lib/systemd/system/' + dm, root + '/etc/systemd/system/display-manager.service')
        for path, text in files.items():
            os.makedirs(os.path.dirname(root + path), exist_ok=True)
            open(root + path, 'w').write(text)
        got = load(root).autologin_user()
        ok = got == expect
        results.append(ok)
        print('%-52s %s  got %r' % (name, 'PASS' if ok else 'FAIL', got))
    finally:
        shutil.rmtree(root)
case('no display manager', None, {}, None)
case('Plasma Login Manager, no autologin', 'plasmalogin.service', {'/etc/plasmalogin.conf': '[General]\n'}, None)
case('Plasma Login Manager, autologin stereo', 'plasmalogin.service', {'/etc/plasmalogin.conf': '[Autologin]\nUser=stereo\nSession=plasma\n'}, 'stereo')
case('SDDM, conf.d empty user', 'sddm.service', {'/etc/sddm.conf.d/kde_settings.conf': '[Autologin]\nUser=\n'}, None)
case('SDDM, sddm.conf wins over conf.d', 'sddm.service', {'/etc/sddm.conf.d/kde_settings.conf': '[Autologin]\nUser=\n', '/etc/sddm.conf': '[Autologin]\nUser=daniel\n'}, 'daniel')
case('SDDM, User= in another group is not autologin', 'sddm.service', {'/etc/sddm.conf': '[Users]\nUser=daniel\n'}, None)
case('SDDM file of the other display manager ignored', 'plasmalogin.service', {'/etc/sddm.conf': '[Autologin]\nUser=daniel\n'}, None)
print('SUMMARY %d of %d pass' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
