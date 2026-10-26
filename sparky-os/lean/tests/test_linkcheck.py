"""The link gate must reject the torcs failure (a library dropped from NEEDED that a sibling still uses)."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import archive, linkcheck, package, release
from lean.tests.archive_fixtures import signed_archive

LIBDIR = 'usr/lib/x86_64-linux-gnu/demo/lib'


@unittest.skipUnless(shutil.which('gcc') and shutil.which('dpkg-deb') and shutil.which('ldd'), 'needs gcc, dpkg-deb, ldd')
class LinkGate(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='test-link-')
        self.addCleanup(self.work.cleanup)
        self.base = Path(self.work.name)
        self.context = archive.Archive(signed_archive(self.base / 'archive'), self.base / 'scratch', 'amd64')
        src = self.base / 'src'
        src.mkdir()
        (src / 'b.c').write_text('int xrr_current(void) { return 7; }\n')
        (src / 'a.c').write_text('int xrr_current(void);\nint client_size(void) { return xrr_current(); }\n')
        (src / 'm.c').write_text('int client_size(void);\nint main(void) { return client_size() == 7 ? 0 : 1; }\n')
        self.src = src
        # libb stands for libXrandr, liba for libtgfclient (uses it, does not list it), m for torcs-bin.
        self.run_cc(['-shared', '-fPIC', '-o', 'libb.so.1', '-Wl,-soname,libb.so.1', 'b.c'])
        self.run_cc(['-shared', '-fPIC', '-o', 'liba.so', 'a.c'])

    def check(self, *args, **kwargs):
        return linkcheck.check(*args, archive_context=self.context, **kwargs)

    def run_cc(self, args):
        subprocess.run(['gcc'] + args, cwd=self.src, check=True)

    def deb(self, name, version, as_needed, listed=True, broken_depends=False):
        root = self.base / f'pkg-{version}'
        (root / LIBDIR).mkdir(parents=True)
        (root / 'usr/games').mkdir()
        (root / 'DEBIAN').mkdir()
        shutil.copy(self.src / 'libb.so.1', root / LIBDIR / 'libb.so.1')
        shutil.copy(self.src / 'liba.so', root / LIBDIR / 'liba.so')
        flag = '-Wl,--as-needed' if as_needed else '-Wl,--no-as-needed'
        # --as-needed with the unused library listed before its only user drops it from NEEDED,
        # which is the situation of libXrandr in torcs-bin (its user, libtgfclient, does not list it).
        order = ['-l:libb.so.1', '-la'] if as_needed else ['-la', '-l:libb.so.1']
        self.run_cc(['-o', str(root / 'usr/games/demo'), 'm.c', f'-L{root / LIBDIR}', flag] + order +
                    ['-Wl,--allow-shlib-undefined', f'-Wl,-rpath-link,{root / LIBDIR}'])
        depends = 'libc6' + (', libxrandr2' if listed else '')
        (root / 'DEBIAN/control').write_text(
            f'Package: {name}\nVersion: {version}\nArchitecture: amd64\nMaintainer: t <t@example.org>\n'
            f'Description: t\nDepends: {depends}\n')
        out = self.base / f'{name}_{version}_amd64.deb'
        subprocess.run(['dpkg-deb', '--build', str(root), str(out)], check=True, stdout=subprocess.DEVNULL)
        return out

    def test_loader_error_is_rejected(self):
        # A needed library that the loader cannot use (not an ELF file: masked, truncated, the wrong class)
        # is neither "not found" nor an undefined symbol; it is still a program that does not start.
        deb = self.deb('demo', '5+lc1', as_needed=False)
        root = self.base / 'pkg-5+lc1'
        (root / LIBDIR / 'libb.so.1').write_bytes(b'not an ELF file\n')
        subprocess.run(['dpkg-deb', '--build', str(root), str(deb)], check=True, stdout=subprocess.DEVNULL)
        with self.assertRaises(package.Invalid) as raised:
            self.check(deb)
        self.assertIn('loader error', str(raised.exception))
        self.assertIn('libb.so.1', str(raised.exception))

    def test_dropped_needed_is_rejected(self):
        before = self.deb('demo', '1', as_needed=False)
        after = self.deb('demo', '1+lc1', as_needed=True, listed=False)
        exe = self.base / 'pkg-1+lc1/usr/games/demo'
        if 'libb.so.1' in linkcheck.needed(exe):
            self.skipTest('this linker kept the library; nothing to reproduce')
        # Without a previous build the library's own undefined symbol is a finding, with one it is known noise.
        self.assertEqual(self.check(before, previous_deb=before), [])
        with self.assertRaises(package.Invalid) as raised:
            self.check(after, previous_deb=before)
        self.assertIn('xrr_current', str(raised.exception))

    def test_smoke_start_catches_loader_error(self):
        after = self.deb('demo', '2+lc1', as_needed=True, listed=False)
        exe = self.base / 'pkg-2+lc1/usr/games/demo'
        if 'libb.so.1' in linkcheck.needed(exe):
            self.skipTest('this linker kept the library; nothing to reproduce')
        table = self.base / 'smoke.tsv'
        table.write_text('demo\t/usr/games/demo\t--version\n')
        findings = linkcheck.smoke(after, table, qualified=self.context.qualify(after))
        self.assertTrue(findings and 'xrr_current' in findings[0], findings)

    def test_lost_stereo_feature_is_rejected(self):
        (self.src / 'a.c').write_text('int xrr_current(void);\nint stereo_declare_x11(void) { return 0; }\n'
                                      'int client_size(void) { return xrr_current(); }\n')
        (self.src / 'sd.c').write_text('int stereo_declare_x11(void) { return 1; }\n')
        self.run_cc(['-shared', '-fPIC', '-o', 'libstereo-declare.so.1', '-Wl,-soname,libstereo-declare.so.1', 'sd.c'])
        # previous: the program calls into libstereo-declare; rebuilt: the call was compiled out
        (self.src / 'm1.c').write_text('int client_size(void);\nint stereo_declare_x11(void);\n'
                                       'int main(void) { return stereo_declare_x11() + client_size() == 7 ? 0 : 1; }\n')
        (self.src / 'm2.c').write_text('int client_size(void);\nint main(void) { return client_size() == 7 ? 0 : 1; }\n')
        def pack(version, main_c):
            root = self.base / f'pkg-s{version}'
            (root / LIBDIR).mkdir(parents=True)
            (root / 'usr/games').mkdir()
            (root / 'DEBIAN').mkdir()
            for lib in ('libb.so.1', 'liba.so', 'libstereo-declare.so.1'):
                shutil.copy(self.src / lib, root / LIBDIR / lib)
            self.run_cc(['-o', str(root / 'usr/games/demo'), main_c, f'-L{root / LIBDIR}', '-la', '-l:libb.so.1',
                         '-l:libstereo-declare.so.1', f'-Wl,-rpath-link,{root / LIBDIR}'])
            (root / 'DEBIAN/control').write_text(f'Package: sdemo\nVersion: {version}\nArchitecture: amd64\n'
                                                 'Maintainer: t <t@example.org>\nDescription: t\nDepends: libc6\n')
            out = self.base / f'sdemo_{version}_amd64.deb'
            subprocess.run(['dpkg-deb', '--build', str(root), str(out)], check=True, stdout=subprocess.DEVNULL)
            return out
        before, after = pack('1', 'm1.c'), pack('1+lc1', 'm2.c')
        self.assertEqual(self.check(before, previous_deb=before), [])
        with self.assertRaises(package.Invalid) as raised:
            self.check(after, previous_deb=before)
        self.assertIn('stereo imports lost', str(raised.exception))

    def test_same_link_passes(self):
        before = self.deb('demo', '3', as_needed=False)
        after = self.deb('demo', '3+lc1', as_needed=False)
        table = self.base / 'smoke.tsv'
        table.write_text('demo\t/usr/games/demo\t--version\n')
        self.assertEqual(self.check(after, previous_deb=before, smoke_table=table), [])

    def test_sibling_library_is_found_and_previous_build_is_chosen(self):
        """A plugin links the library a sibling package ships; the newest older build is the baseline."""
        client = self.deb('demo', '4+lc1', as_needed=False)
        sibling = self.base / 'libb-pkg'
        (sibling / 'usr/lib/x86_64-linux-gnu').mkdir(parents=True)
        (sibling / 'DEBIAN').mkdir()
        shutil.copy(self.src / 'libb.so.1', sibling / 'usr/lib/x86_64-linux-gnu/libb.so.1')
        (sibling / 'DEBIAN/control').write_text('Package: libb\nVersion: 4\nArchitecture: amd64\n'
                                                'Maintainer: t <t@example.org>\nDescription: t\n')
        libb = self.base / 'libb_4_amd64.deb'
        subprocess.run(['dpkg-deb', '--build', str(sibling), str(libb)], check=True, stdout=subprocess.DEVNULL)
        (self.base / 'pkg-4+lc1' / LIBDIR / 'libb.so.1').unlink()
        subprocess.run(['dpkg-deb', '--build', str(self.base / 'pkg-4+lc1'), str(client)], check=True, stdout=subprocess.DEVNULL)
        with self.assertRaises(package.Invalid):
            self.check(client)
        self.check(client, siblings=[libb])
        older, newer = self.deb('demo', '3', as_needed=False), self.deb('demo', '3.5', as_needed=False)
        previous = self.base / 'previous'
        previous.mkdir()
        for deb in (older, newer, self.deb('demo', '9', as_needed=False)):
            shutil.copy(deb, previous)
        self.assertEqual(release.previous_build(client, previous).name, newer.name)


if __name__ == '__main__':
    unittest.main()


def test_static_elf_passes_in_any_locale(tmp_path, monkeypatch):
    """A static ELF (a kernel's vmlinux, a static tool) is not a loader error, whatever the host's language."""
    import shutil, subprocess
    cc = shutil.which('cc') or shutil.which('gcc')
    if not cc:
        import pytest; pytest.skip('no C compiler')
    src = tmp_path / 's.c'; src.write_text('int main(void){return 0;}\n')
    root = tmp_path / 'root'; (root / 'usr/bin').mkdir(parents=True)
    exe = root / 'usr/bin/static-tool'
    if subprocess.run([cc, '-static', '-o', str(exe), str(src)], capture_output=True).returncode != 0:
        import pytest; pytest.skip('no static libc')
    monkeypatch.setenv('LC_ALL', 'pt_BR.UTF-8'); monkeypatch.setenv('LANG', 'pt_BR.UTF-8')
    from lean import linkcheck
    from lean import archive
    from lean.tests.archive_fixtures import signed_archive, deb
    binary = deb(tmp_path / 'pkg', 'static-fixture', files={'usr/bin/static-tool': exe})
    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    assert linkcheck.resolve(root, qualified=context.qualify(binary)) == {}
