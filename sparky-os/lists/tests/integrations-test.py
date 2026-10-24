#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Checks of the stereo integration mechanism that need no container: the list and its validation, the AppCenter map, the
# pack generator and its nine-language gate, and the runner's HideMissing sync. Run: python3 -m unittest -v lists/tests/integrations-test.py
import json, os, pathlib, subprocess, sys, tempfile, unittest

# Lanes never reach a person's desktop: refuse to run inside a graphical session (a dialog could open on it).
if os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
    sys.exit('integrations-test: DISPLAY or WAYLAND_DISPLAY is set; run it with env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR')

ROOT = pathlib.Path(__file__).resolve().parents[2]
LISTS = ROOT / 'lists'
sys.path.insert(0, str(LISTS))
import integrations

PKG = ROOT / 'packages' / 'sparky-stereo-integration'
LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']


def spec(**over):
    s = {'id': 't', 'program': 'tprog', 'worker': '/usr/lib/t/w',
         'menus': [{'file': 'sparky-stereo-t', 'mime': ['video/x-matroska'], 'urls': {'min': 1},
                    'submenu': {l: 'Sub ' + l for l in LANGS},
                    'actions': [{'id': 'A', 'args': ['1'], 'name': {l: 'Act ' + l for l in LANGS}}]}]}
    s.update(over)
    return s


class ListTest(unittest.TestCase):
    def write(self, text):
        f = tempfile.NamedTemporaryFile('w', suffix='.tsv', delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_shipped_list_reads(self):
        rows = integrations.read()
        self.assertIn('sparky-stereo-align', [r['pack'] for r in rows])
        self.assertIn('sparky-stereo-mkv-mark', [r['pack'] for r in rows])
        self.assertTrue(all(r['kind'] in integrations.KINDS for r in rows))

    def test_bad_rows_stop(self):
        for text in ('hugin-tools\tsparky-stereo-align\tweird\n', 'hugin-tools\tnot-ours\tdata\n',
                     'a\tsparky-stereo-x\tdata\na\tsparky-stereo-x\tdata\n', 'only-one-column\n'):
            with self.assertRaises(SystemExit):
                integrations.read(self.write(text))

    def test_map_joins_packs_of_one_program(self):
        rows = integrations.read(self.write('p\tsparky-stereo-b\tdata\np\tsparky-stereo-a\tnative\nq\tsparky-stereo-c\tdata\n'))
        self.assertEqual(integrations.appcenter_map(rows), 'p\tsparky-stereo-a sparky-stereo-b\nq\tsparky-stereo-c\n')
        self.assertEqual(integrations.appcenter_map(rows, lambda p: p != 'sparky-stereo-b'), 'p\tsparky-stereo-a\nq\tsparky-stereo-c\n')


class GeneratorTest(unittest.TestCase):
    def run_gen(self, s):
        d = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ['rm', '-rf', d])
        (pathlib.Path(d) / 'pack.json').write_text(json.dumps(s))
        r = subprocess.run([sys.executable, str(PKG / 'make-pack.py'), d + '/pack.json', d + '/out'], capture_output=True, text=True)
        return r, pathlib.Path(d) / 'out'

    def test_menu_and_conf(self):
        r, out = self.run_gen(spec())
        self.assertEqual(r.returncode, 0, r.stderr)
        text = (out / 'usr/share/kio/servicemenus/sparky-stereo-t.desktop').read_text()
        self.assertIn('MimeType=video/x-matroska;', text)
        self.assertIn('X-KDE-MinNumberOfUrls=1', text)
        self.assertIn('Exec=sparky-stereo-integration run t 1 -- %F', text)
        for l in LANGS[1:]:
            self.assertIn(f'Name[{l}]=Act {l}', text)
            self.assertIn(f'X-KDE-Submenu[{l}]=Sub {l}', text)
        self.assertEqual((out / 'usr/share/sparky-stereo/integrations.d/t.conf').read_text(),
                         'program=tprog\nworker=/usr/lib/t/w\nmenus=sparky-stereo-t.desktop\n')

    def test_a_missing_language_stops(self):
        s = spec()
        del s['menus'][0]['actions'][0]['name']['de']
        r, out = self.run_gen(s)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('lacks de', r.stderr)

    def test_a_semicolon_stops(self):
        s = spec()
        s['menus'][0]['actions'][0]['name']['ja'] = 'a;b'
        r, out = self.run_gen(s)
        self.assertNotEqual(r.returncode, 0)


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.d = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ['rm', '-rf', str(self.d)])
        (self.d / 'conf').mkdir(); (self.d / 'menus').mkdir(); (self.d / 'bin').mkdir(); (self.d / 'home').mkdir()
        (self.d / 'conf/t.conf').write_text('program=tprog\nworker=/bin/true\nmenus=sparky-stereo-t.desktop\n')
        (self.d / 'menus/sparky-stereo-t.desktop').write_text('[Desktop Entry]\nType=Service\nMimeType=video/x-matroska;\nActions=A;\n')
        (self.d / 'sys.rc').write_text('[General]\nHideMissing=false\n')
        self.env = dict(HOME=str(self.d / 'home'), XDG_CONFIG_HOME=str(self.d / 'home/.config'), XDG_DATA_HOME=str(self.d / 'home/.local/share'),
                        SPARKY_STEREO_INTEGRATIONS_D=str(self.d / 'conf'), SPARKY_STEREO_SERVICEMENUS=str(self.d / 'menus'),
                        SPARKY_STEREO_INTEGRATION_SYSRC=str(self.d / 'sys.rc'), SPARKY_STEREO_INTEGRATION_LANGDIR=str(PKG / 'lang'),
                        PATH=str(self.d / 'bin') + ':/usr/bin:/bin', LANG='C', LC_ALL='C', SPARKY_STEREO_INTEGRATION_UI='none')
        self.user = self.d / 'home/.local/share/kio/servicemenus/sparky-stereo-t.desktop'

    def run_cli(self, *args):
        return subprocess.run(['bash', str(PKG / 'bin/sparky-stereo-integration'), *args], env=self.env, capture_output=True, text=True)

    def program(self, present):
        p = self.d / 'bin/tprog'
        if present:
            p.write_text('#!/bin/sh\n'); p.chmod(0o755)
        elif p.exists():
            p.unlink()

    def test_default_is_off_and_writes_nothing(self):
        self.assertEqual(self.run_cli('hide-missing', 'status').stdout.strip(), 'false')
        self.run_cli('hide-missing', 'sync')
        self.assertFalse(self.user.exists())

    def test_on_missing_present_and_off(self):
        self.program(False)
        self.run_cli('hide-missing', 'on')
        text = self.user.read_text()
        self.assertIn('TryExec=tprog', text)
        self.assertIn('X-Sparky-Stereo-Override=true', text)
        self.assertIn('\nMimeType=\n', text)
        self.program(True)
        self.run_cli('hide-missing', 'sync')
        text = self.user.read_text()
        self.assertIn('MimeType=video/x-matroska;', text)
        self.assertIn('TryExec=tprog', text)
        self.run_cli('hide-missing', 'off')
        self.assertFalse(self.user.exists())
        self.assertEqual(self.run_cli('hide-missing', 'status').stdout.strip(), 'false')

    def test_a_file_of_the_persons_is_never_touched(self):
        self.user.parent.mkdir(parents=True)
        self.user.write_text('[Desktop Entry]\nName=mine\n')
        self.run_cli('hide-missing', 'on'); self.run_cli('hide-missing', 'off')
        self.assertEqual(self.user.read_text(), '[Desktop Entry]\nName=mine\n')

    def test_system_default_true_and_users_false_wins(self):
        (self.d / 'sys.rc').write_text('[General]\nHideMissing=true\n')
        self.assertEqual(self.run_cli('hide-missing', 'status').stdout.strip(), 'true')
        self.run_cli('hide-missing', 'off')
        self.assertEqual(self.run_cli('hide-missing', 'status').stdout.strip(), 'false')

    def test_missing_program_without_a_desktop_exits_127(self):
        self.program(False)
        r = self.run_cli('run', 't', '1', '--', '/nonexistent')
        self.assertEqual(r.returncode, 127)
        self.assertIn('tprog', r.stderr)  # command-not-found's own words, or ours when it is absent

    def test_present_program_runs_the_worker_with_the_arguments(self):
        self.program(True)
        w = self.d / 'worker'
        w.write_text(f'#!/bin/sh\necho "$@" > {self.d}/args\n'); w.chmod(0o755)
        (self.d / 'conf/t.conf').write_text(f'program=tprog\nworker={w}\nmenus=sparky-stereo-t.desktop\n')
        r = self.run_cli('run', 't', '3', 'swap', '--', 'a b.mkv')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.d / 'args').read_text().strip(), '3 swap -- a b.mkv')


class ContentsTest(unittest.TestCase):
    def deb(self, d, name, arch, files):
        root = pathlib.Path(d) / name
        (root / 'DEBIAN').mkdir(parents=True)
        for f in files:
            (root / f).parent.mkdir(parents=True, exist_ok=True)
            (root / f).write_text('x')
        (root / 'DEBIAN/control').write_text(f'Package: {name}\nVersion: 1\nArchitecture: {arch}\nMaintainer: t <t@example.invalid>\nSection: Utilities\nDescription: t\n t\n')
        out = pathlib.Path(d) / f'{name}_1_{arch}.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(root), str(out)], check=True, capture_output=True)
        return str(out)

    def test_format_arch_all_and_owners(self):
        d = tempfile.mkdtemp()
        self.addCleanup(subprocess.run, ['rm', '-rf', d])
        a = self.deb(d, 'pa', 'amd64', ['usr/bin/tool', 'usr/share/pa/x'])
        b = self.deb(d, 'pb', 'all', ['usr/share/pb/y', 'usr/share/pa/x'])
        c = self.deb(d, 'pc', 'i386', ['usr/bin/tool32'])
        out = pathlib.Path(d) / 'out'
        r = subprocess.run([sys.executable, str(ROOT / 'repo/make-contents.py'), str(out), 'amd64 i386 all', a, b, c], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        amd64 = (out / 'Contents-amd64').read_text().splitlines()
        self.assertIn('usr/bin/tool\tutilities/pa', amd64)
        self.assertIn('usr/share/pb/y\tutilities/pb', amd64)
        self.assertIn('usr/share/pa/x\tutilities/pa,utilities/pb', amd64)
        self.assertEqual(amd64, sorted(amd64))
        self.assertNotIn('usr/bin/tool32', '\n'.join(amd64))
        self.assertIn('usr/bin/tool32\tutilities/pc', (out / 'Contents-i386').read_text().splitlines())
        self.assertEqual((out / 'Contents-all').read_text().splitlines(), ['usr/share/pa/x\tutilities/pb', 'usr/share/pb/y\tutilities/pb'])
        self.assertFalse(any(l.endswith('/') or l.startswith('./') for l in amd64))


if __name__ == '__main__':
    unittest.main()
