"""The link gate must reject the torcs failure (a library dropped from NEEDED that a sibling still uses)."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import pytest

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
        depends = 'libc6' + (', libxrandr2' if listed else '') + (', libb' if broken_depends else '')
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
        client = self.deb('demo', '4+lc1', as_needed=False, broken_depends=True)
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


# ORDER 340: an ELF file the host's dynamic loader never loads. qemu-system-data (Architecture: all) ships
# QEMU's guest firmware in /usr/share/qemu, and QEMU's machine models read it with load_elf() into the guest
# (hw/hppa/machine.c, hw/ppc/mac_newworld.c, hw/sparc/sun4m.c, hw/sparc64/sun4u.c). Each shape below is the
# readelf -h -l -d of one such file in qemu-system-data 1:11.1.2+ds-3+stereo3d6+lc1 and +stereo3d7+lc1: its
# class, byte order, e_type, e_machine, and PT_INTERP and PT_DYNAMIC where it has them.
GUEST_FIRMWARE = {
    'hppa-firmware.img': dict(machine=15),
    'hppa-firmware64.img': dict(machine=15, bits=64, interp='/usr/lib/pa20_64/dld.sl', dynamic=True),
    'openbios-ppc': dict(machine=20),
    'openbios-sparc32': dict(machine=2),
    'openbios-sparc64': dict(machine=43, bits=64),
    'palcode-clipper': dict(machine=0x9026, bits=64, big=False),
    's390-ccw.img': dict(machine=22, bits=64, kind=3, dynamic=True),
    'u-boot.e500': dict(machine=20),
}


def foreign_elf(machine, bits=32, big=True, kind=2, interp=None, dynamic=False):
    """A minimal ELF file: its header, and a PT_INTERP and a PT_DYNAMIC segment when asked for."""
    import struct
    e, word = ('>' if big else '<'), ('Q' if bits == 64 else 'I')
    ehsize, phentsize = (64, 56) if bits == 64 else (52, 32)
    count = bool(interp) + bool(dynamic)
    segments, payload, base = [], b'', ehsize + phentsize * count
    for kind_, data in ((3, (interp or '').encode() + b'\0'), (2, struct.pack(e + word * 2, 0, 0))):
        if (kind_ == 3 and interp) or (kind_ == 2 and dynamic):
            segments.append((kind_, base + len(payload), len(data)))
            payload += data
    header = b'\x7fELF' + bytes([2 if bits == 64 else 1, 2 if big else 1, 1]) + bytes(9)
    header += struct.pack(e + 'HHI' + word * 3 + 'IHHHHHH', kind, machine, 1, 0x10000, ehsize if count else 0, 0,
                          0, ehsize, phentsize, count, 0, 0, 0)
    for kind_, offset, size in segments:
        header += (struct.pack(e + 'IIQQQQQQ', kind_, 4, offset, offset, offset, size, size, 1) if bits == 64 else
                   struct.pack(e + 'IIIIIIII', kind_, offset, offset, offset, size, size, 4, 1))
    return header + payload


def with_machine(path, machine):
    """The bytes of an ELF file built here, with another e_machine (the foreign-dynamic negative of lane 255)."""
    import struct
    data = bytearray(Path(path).read_bytes())
    struct.pack_into('<H' if data[5] == 1 else '>H', data, 18, machine)
    return bytes(data)


def gate_resolve(tmp_path, context, deb, notes=None):
    root = tmp_path / ('root-' + deb.name)
    root.mkdir()
    linkcheck.extract(deb, root)
    qualified = context.qualify(deb)
    try:
        return linkcheck.resolve(root, qualified=qualified, **({} if notes is None else {'notes': notes}))
    finally:
        qualified.close()


needs_tools = pytest.mark.skipif(not (shutil.which('gcc') and shutil.which('dpkg-deb') and shutil.which('bwrap')),
                                 reason='needs gcc, dpkg-deb, bwrap')


@needs_tools
def test_guest_firmware_is_data_not_a_host_object(tmp_path):
    """The published and the rebuilt qemu-system-data pass: their guest firmware is noted, never loaded."""
    from lean.tests.archive_fixtures import signed_archive, deb
    files = {f'usr/share/qemu/{name}': foreign_elf(**shape) for name, shape in GUEST_FIRMWARE.items()}
    old = deb(tmp_path / 'old', 'qemu-system-data', '1:11.1.2+ds-3+stereo3d6+lc1', arch='all', files=files)
    new = deb(tmp_path / 'new', 'qemu-system-data', '1:11.1.2+ds-3+stereo3d7+lc1', arch='all', files=files)
    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    noted = linkcheck.check(new, previous_deb=old, archive_context=context)
    assert len([note for note in noted if 'another consumer' in note]) == len(GUEST_FIRMWARE), noted
    assert any(note.startswith('/usr/share/qemu/hppa-firmware64.img: HPPA ELF') for note in noted), noted
    notes = []
    assert gate_resolve(tmp_path, context, old, notes) == {}
    assert sorted(note.split(':', 1)[0] for note in notes) == sorted(f'/{path}' for path in files)
    assert all('another consumer' in note for note in notes), notes


@needs_tools
def test_foreign_elf_the_host_may_load_still_fails(tmp_path):
    """A foreign library in a library directory, a foreign module, a foreign program, or guest firmware in an
    architecture-dependent package is the host's: each still fails the machine check."""
    from lean.tests.archive_fixtures import signed_archive, deb
    (tmp_path / 'lib.c').write_text('int foreign(void) { return 1; }\n')
    (tmp_path / 'main.c').write_text('int main(void) { return 0; }\n')
    subprocess.run(['gcc', '-shared', '-fPIC', '-o', str(tmp_path / 'libforeign.so.1'), str(tmp_path / 'lib.c')], check=True)
    subprocess.run(['gcc', '-o', str(tmp_path / 'tool'), str(tmp_path / 'main.c')], check=True)
    library = with_machine(tmp_path / 'libforeign.so.1', 183)
    program = with_machine(tmp_path / 'tool', 40)
    firmware = foreign_elf(**GUEST_FIRMWARE['hppa-firmware64.img'])
    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    independent = deb(tmp_path / 'all', 'foreign-all', arch='all', files={
        'usr/lib/x86_64-linux-gnu/libforeign.so.1': library,
        'usr/lib/x86_64-linux-gnu/qemu/block-foreign.so': library,
        'usr/bin/foreign-tool': program,
        'usr/share/qemu/hppa-firmware64.img': firmware})
    dependent = deb(tmp_path / 'any', 'foreign-any', arch='amd64', files={
        'usr/lib/x86_64-linux-gnu/libforeign.so.1': library,
        'usr/share/qemu/hppa-firmware64.img': firmware,
        'usr/share/qemu/openbios-ppc': foreign_elf(**GUEST_FIRMWARE['openbios-ppc'])})
    refused = ('loader error', 'ELF machine does not match amd64')
    assert gate_resolve(tmp_path, context, independent) == {
        ('/usr/bin/foreign-tool',) + refused: True,
        ('/usr/lib/x86_64-linux-gnu/libforeign.so.1',) + refused: True,
        ('/usr/lib/x86_64-linux-gnu/qemu/block-foreign.so',) + refused: True}
    assert gate_resolve(tmp_path, context, dependent) == {
        ('/usr/lib/x86_64-linux-gnu/libforeign.so.1',) + refused: True,
        ('/usr/share/qemu/hppa-firmware64.img',) + refused: True,
        ('/usr/share/qemu/openbios-ppc',) + refused: True}
    for candidate in (independent, dependent):
        with pytest.raises(package.Invalid, match='ELF machine does not match amd64'):
            linkcheck.check(candidate, archive_context=context)


@needs_tools
def test_usr_share_is_no_blanket_skip(tmp_path):
    """Under /usr/share of an Architecture: all package, an ELF of the host's machine is still traced, and a
    file that only starts like ELF is still unusable: the rule is the foreign machine, not the place."""
    from lean.tests.archive_fixtures import signed_archive, deb
    (tmp_path / 'missing.c').write_text('int missing(void) { return 1; }\n')
    (tmp_path / 'main.c').write_text('int missing(void);\nint main(void) { return missing(); }\n')
    subprocess.run(['gcc', '-shared', '-fPIC', '-o', str(tmp_path / 'libmissing.so.1'), '-Wl,-soname,libmissing.so.1',
                    str(tmp_path / 'missing.c')], check=True)
    subprocess.run(['gcc', '-o', str(tmp_path / 'tool'), str(tmp_path / 'main.c'), str(tmp_path / 'libmissing.so.1')],
                   check=True)
    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    candidate = deb(tmp_path / 'all', 'share-all', arch='all', depends='libc6', files={
        'usr/share/demo/tool': tmp_path / 'tool',
        'usr/share/qemu/truncated.img': b'\x7fELF\x01\x02\x01' + bytes(9)})
    found = gate_resolve(tmp_path, context, candidate)
    assert found.pop(('/usr/share/demo/tool', 'not found', 'libmissing.so.1')) is True
    assert found.pop(('/usr/share/demo/tool', 'undefined', 'missing')) is True
    assert [key[:2] for key in found] == [('/usr/share/qemu/truncated.img', 'loader error')], found
    assert next(iter(found))[2].startswith('unusable ELF: ')


def test_lane_255_probe_controls_unchanged(tmp_path):
    """Lane 255's probe: loader_command accepts a native static program as static and refuses a foreign dynamic one."""
    import types
    cc = shutil.which('gcc')
    if not cc:
        pytest.skip('no C compiler')
    (tmp_path / 'control.c').write_text('int main(void) { return 0; }\n')
    exe = tmp_path / 'native-static'
    if subprocess.run([cc, '-static', '-O2', '-o', str(exe), str(tmp_path / 'control.c')]).returncode:
        pytest.skip('no static libc')
    qualified = types.SimpleNamespace(arch='amd64', root=tmp_path)
    command, static = linkcheck.loader_command(exe, tmp_path, qualified)
    assert static and command == ['/native-static']
    mutant = tmp_path / 'foreign-dynamic-negative'
    mutant.write_bytes(with_machine('/usr/bin/true', 40))
    with pytest.raises(package.Invalid, match='^ELF machine does not match amd64$'):
        linkcheck.loader_command(mutant, tmp_path, qualified)


@needs_tools
def test_static_pie_program_needs_no_loader(tmp_path):
    """qemu-user's programs are static-pie (ET_DYN, DF_1_PIE, no interpreter, no NEEDED) and its package depends
    on no libc: they start with no loader, like any static program. A library without NEEDED is still traced."""
    from lean.tests.archive_fixtures import signed_archive, deb
    (tmp_path / 'main.c').write_text('int main(void) { return 0; }\n')
    (tmp_path / 'lib.c').write_text('int ext(void);\nint f(void) { return ext(); }\n')
    if subprocess.run(['gcc', '-static-pie', '-o', str(tmp_path / 'qemu-demo'), str(tmp_path / 'main.c')]).returncode:
        pytest.skip('no static-pie libc')
    subprocess.run(['gcc', '-shared', '-fPIC', '-nostdlib', '-o', str(tmp_path / 'libnoneeded.so'),
                    str(tmp_path / 'lib.c')], check=True)
    assert 'Flags: PIE' in subprocess.run(['readelf', '-d', '-W', str(tmp_path / 'qemu-demo')], capture_output=True,
                                          text=True, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}).stdout
    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    static = deb(tmp_path / 'user', 'qemu-user-demo', files={'usr/bin/qemu-demo': tmp_path / 'qemu-demo'})
    library = deb(tmp_path / 'lib', 'noneeded-demo', depends='libc6',
                  files={'usr/lib/x86_64-linux-gnu/libnoneeded.so': tmp_path / 'libnoneeded.so'})
    assert gate_resolve(tmp_path, context, static) == {}
    assert linkcheck.check(static, previous_deb=static, archive_context=context) == []
    assert gate_resolve(tmp_path, context, library) == {('/usr/lib/x86_64-linux-gnu/libnoneeded.so', 'undefined', 'ext'): True}
