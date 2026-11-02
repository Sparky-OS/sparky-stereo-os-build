"""U58 (ORDER 346b): an ELF inventory that readelf or nm could not read is never an empty inventory.

The link gate compares each file's NEEDED libraries and stereo imports with the previous build's. A failed probe
used to give an empty inventory, the same as a file that imports nothing, so a predecessor whose nm failed hid the
stereo import its rebuild lost. The failures are injected only into the inventory calls (readelf -d, nm -D), never
into the loader tracing or the guest-data check, and the real tools give the controls.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import archive, linkcheck, package
from lean.tests.archive_fixtures import signed_archive

LIBDIR = 'usr/lib/x86_64-linux-gnu/demo/lib'
needs_cc = pytest.mark.skipif(not shutil.which('gcc'), reason='needs gcc')
needs_gate = pytest.mark.skipif(not (shutil.which('gcc') and shutil.which('dpkg-deb') and shutil.which('bwrap')),
                                reason='needs gcc, dpkg-deb, bwrap')


def failing(tool, when=lambda path: True):
    """subprocess.run, with TOOL's inventory call (readelf -d, nm -D) failing the way binutils fails on a file it
    cannot read; every other command runs for real."""
    real = subprocess.run
    flag = {'readelf': '-d', 'nm': '-D'}[tool]

    def run(args, *a, **k):
        if isinstance(args, list) and args[:2] == [tool, flag] and when(str(args[-1])):
            return subprocess.CompletedProcess(args, 1, '', f'{tool}: {args[-1]}: file format not recognized\n')
        return real(args, *a, **k)
    return run


def program(tmp_path, static=False):
    (tmp_path / 'p.c').write_text('int main(void) { return 0; }\n')
    exe = tmp_path / ('static-p' if static else 'p')
    run = subprocess.run(['gcc'] + (['-static'] if static else []) + ['-o', str(exe), str(tmp_path / 'p.c')],
                         capture_output=True)
    if run.returncode:
        pytest.skip('no static libc' if static else 'gcc failed')
    return exe


@needs_cc
def test_failed_readelf_is_not_an_empty_inventory(tmp_path, monkeypatch):
    exe = program(tmp_path)
    monkeypatch.setattr(linkcheck.subprocess, 'run', failing('readelf'))
    with pytest.raises(package.Invalid, match='cannot verify the NEEDED libraries of .*readelf -d -W exited 1: '
                                             'readelf: .*file format not recognized'):
        linkcheck.needed(exe)


@needs_cc
def test_failed_nm_is_not_an_empty_inventory(tmp_path, monkeypatch):
    exe = program(tmp_path)
    monkeypatch.setattr(linkcheck.subprocess, 'run', failing('nm'))
    with pytest.raises(package.Invalid, match='cannot verify the stereo imports of .*nm -D --undefined-only exited 1'):
        linkcheck.stereo_imports(exe)


@needs_cc
def test_readable_inventories_are_read(tmp_path):
    """The controls: a dynamic program lists libc and imports no stereo symbol; a static one has a readable, empty
    inventory (readelf "There is no dynamic section", nm "no symbols", both exit 0)."""
    exe = program(tmp_path)
    assert 'libc.so.6' in linkcheck.needed(exe)
    assert linkcheck.stereo_imports(exe) == set()
    static = program(tmp_path, static=True)
    assert linkcheck.needed(static) == []
    assert linkcheck.stereo_imports(static) == set()


@pytest.fixture
def stereo_pair(tmp_path):
    """sdemo 1 calls stereo_declare_x11; its rebuild 1+lc1 lost the call (analitza's case), as in test_linkcheck."""
    src = tmp_path / 'src'
    src.mkdir()
    (src / 'b.c').write_text('int xrr_current(void) { return 7; }\n')
    (src / 'a.c').write_text('int xrr_current(void);\nint client_size(void) { return xrr_current(); }\n')
    (src / 'sd.c').write_text('int stereo_declare_x11(void) { return 1; }\n')
    (src / 'm1.c').write_text('int client_size(void);\nint stereo_declare_x11(void);\n'
                              'int main(void) { return stereo_declare_x11() + client_size() == 7 ? 0 : 1; }\n')
    (src / 'm2.c').write_text('int client_size(void);\nint main(void) { return client_size() == 7 ? 0 : 1; }\n')
    cc = lambda *args: subprocess.run(['gcc', *args], cwd=src, check=True)
    cc('-shared', '-fPIC', '-o', 'libb.so.1', '-Wl,-soname,libb.so.1', 'b.c')
    cc('-shared', '-fPIC', '-o', 'liba.so', 'a.c')
    cc('-shared', '-fPIC', '-o', 'libstereo-declare.so.1', '-Wl,-soname,libstereo-declare.so.1', 'sd.c')

    def pack(version, main_c):
        root = tmp_path / f'pkg-s{version}'
        (root / LIBDIR).mkdir(parents=True)
        (root / 'usr/games').mkdir()
        (root / 'DEBIAN').mkdir()
        for lib in ('libb.so.1', 'liba.so', 'libstereo-declare.so.1'):
            shutil.copy(src / lib, root / LIBDIR / lib)
        cc('-o', str(root / 'usr/games/demo'), main_c, f'-L{root / LIBDIR}', '-la', '-l:libb.so.1',
           '-l:libstereo-declare.so.1', f'-Wl,-rpath-link,{root / LIBDIR}')
        (root / 'DEBIAN/control').write_text(f'Package: sdemo\nVersion: {version}\nArchitecture: amd64\n'
                                             'Maintainer: t <t@example.org>\nDescription: t\nDepends: libc6\n')
        out = tmp_path / f'sdemo_{version}_amd64.deb'
        subprocess.run(['dpkg-deb', '--build', str(root), str(out)], check=True, stdout=subprocess.DEVNULL)
        return out

    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    return pack('1', 'm1.c'), pack('1+lc1', 'm2.c'), context


@needs_gate
def test_lost_stereo_import_still_found(stereo_pair):
    """The control: with every probe readable, the lost import is found."""
    before, after, context = stereo_pair
    assert linkcheck.check(before, previous_deb=before, archive_context=context) == []
    with pytest.raises(package.Invalid, match='stereo imports lost: stereo_declare_x11'):
        linkcheck.check(after, previous_deb=before, archive_context=context)


@needs_gate
def test_predecessor_nm_failure_does_not_hide_a_lost_stereo_import(stereo_pair, monkeypatch):
    """The audit's case: nm fails on the previous build, whose program called stereo_declare_x11; the rebuild lost
    the call. An empty predecessor inventory let the rebuild pass."""
    before, after, context = stereo_pair
    monkeypatch.setattr(linkcheck.subprocess, 'run', failing('nm', lambda path: '/inspect-old-' in path))
    with pytest.raises(package.Invalid) as raised:
        linkcheck.check(after, previous_deb=before, archive_context=context)
    message = str(raised.value)
    assert 'cannot verify the stereo imports of /usr/games/demo' in message, message
    assert '/usr/games/demo (the previous build)' in message, message
    assert 'file format not recognized' in message, message


@needs_gate
def test_new_build_readelf_failure_blocks_with_its_reason(stereo_pair, monkeypatch):
    """readelf fails on the rebuild of an unchanged program: the gate names the failed probe, never a pass."""
    before, _, context = stereo_pair
    monkeypatch.setattr(linkcheck.subprocess, 'run', failing('readelf', lambda path: '/inspect-new-' in path))
    with pytest.raises(package.Invalid, match=r'cannot verify the NEEDED libraries of /usr/games/demo.*\(this build\)'
                                              r'|\(this build\).*cannot verify the NEEDED libraries'):
        linkcheck.check(before, previous_deb=before, archive_context=context)
