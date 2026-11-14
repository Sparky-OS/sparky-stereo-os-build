"""U58 (ORDER 346b): an ELF inventory that readelf or nm could not read is never an empty inventory.

The link gate compares each file's NEEDED libraries and stereo imports with the previous build's. A failed probe
used to give an empty inventory, the same as a file that imports nothing, so a predecessor whose nm failed hid the
stereo import its rebuild lost. The failures are injected only into the inventory calls (readelf -d, nm -D), never
into the loader tracing or the guest-data check, and the real tools give the controls.
"""

import json
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
PACK = {}
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

    def pack(version, main_c, retired=None, forge=None):
        """retired: built as an lc1 archive whose manifest records these retired stereo imports (package.prepare, as
        lean.debhelper builds it). forge(root): changes the staged tree after the record was written."""
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
        if retired is not None:
            package.prepare(root, tmp_path / f'hr-s{version}', retired=retired)
        if forge:
            forge(root)
        out = tmp_path / f'sdemo_{version}_amd64.deb'
        subprocess.run(['dpkg-deb', '--build', str(root), str(out)], check=True, stdout=subprocess.DEVNULL)
        return out

    PACK['pack'] = pack

    context = archive.Archive(signed_archive(tmp_path / 'archive'), tmp_path / 'scratch', 'amd64')
    return pack('1', 'm1.c'), pack('1+lc1', 'm2.c'), context


@needs_gate
def test_lost_stereo_import_still_found(stereo_pair):
    """The control: with every probe readable, the lost import is found."""
    before, after, context = stereo_pair
    assert linkcheck.check(before, previous_deb=before, archive_context=context) == []
    with pytest.raises(package.Invalid, match='stereo imports lost: stereo_declare_x11'):
        linkcheck.check(after, previous_deb=before, archive_context=context)


REASON = 'the window is declared through the toolkit now'


@needs_gate
def test_recorded_retirement_lets_only_the_named_import_through(stereo_pair):
    """A call that moved by design: the archive's own lc1 record names the symbol and says why; the gate, which is
    the same code at the build and at publication, notes it and goes on. Another name recorded leaves the block."""
    before, after, context = stereo_pair
    pack = PACK['pack']
    recorded = pack('2+lc1', 'm2.c', retired={'stereo_declare_x11': REASON})
    assert linkcheck.retired_stereo_imports(recorded) == {'stereo_declare_x11': REASON}
    assert linkcheck.retired_stereo_imports(after) == {}
    notes = linkcheck.check(recorded, previous_deb=before, archive_context=context)
    assert any("stereo import stereo_declare_x11 is no longer called, as the package's lc1 record declares: " + REASON in note
               for note in notes), notes
    other = pack('3+lc1', 'm2.c', retired={'stereo_declare_wayland': 'another call moved, not this one'})
    with pytest.raises(package.Invalid, match='stereo imports lost: stereo_declare_x11'):
        linkcheck.check(other, previous_deb=before, archive_context=context)
    # the control: the same rebuild with no record is refused, whatever a file beside the build says
    with pytest.raises(package.Invalid, match='stereo imports lost: stereo_declare_x11'):
        linkcheck.check(after, previous_deb=before, archive_context=context)


@needs_gate
def test_forged_or_reasonless_record_is_refused(stereo_pair, tmp_path):
    """The record is a claim the gate acts on: one written into the manifest after the build (the marker no longer
    matches), one whose marker was recomputed over a row without a reason, and one that names no stereo symbol are
    refused when the archive is read; a build is refused the same rows before it writes anything."""
    before, after, context = stereo_pair
    pack = PACK['pack']

    def manifest(root):
        return root / package.manifest_path('sdemo', 'amd64').lstrip('/')

    def add_record(rows, remark):
        def forge(root):
            path = manifest(root)
            obj = json.loads(path.read_text())
            obj[package.RETIRED] = rows
            raw = package.encode(obj)
            path.write_bytes(raw)
            if remark:
                package.set_fields(root / 'DEBIAN/control', {package.FIELD: f'{package.FORMAT} {package.digest(raw)}'})
        return forge

    # an lc1 archive with no record: the manifest edited afterwards, the marker left as the build wrote it
    edited = pack('4+lc1', 'm2.c', retired={}, forge=add_record({'stereo_declare_x11': REASON}, remark=False))
    with pytest.raises(package.Invalid, match='mismatched lc marker/manifest'):
        linkcheck.check(edited, previous_deb=before, archive_context=context)
    for version, rows, message in (('5+lc1', {'stereo_declare_x11': ''}, 'has no reason'),
                                   ('6+lc1', {'stereo_declare_x11': 'ok'}, 'has no reason'),
                                   ('7+lc1', {'printf': 'not a stereo call at all'}, 'is not the name of a stereo symbol'),
                                   ('8+lc1', {}, 'at least one row'),
                                   ('9+lc1', ['stereo_declare_x11'], 'a table of symbol and reason')):
        forged = pack(version, 'm2.c', retired={}, forge=add_record(rows, remark=True))
        with pytest.raises(package.Invalid, match=message):
            linkcheck.check(forged, previous_deb=before, archive_context=context)
    for rows, message in (({'stereo_declare_x11': ' '}, 'has no reason'), ({'memcpy': REASON}, 'is not the name of a stereo symbol')):
        with pytest.raises(package.Invalid, match=message):
            pack('10+lc1', 'm2.c', retired=rows)
        shutil.rmtree(tmp_path / 'pkg-s10+lc1')


def test_source_declaration_is_read_strictly(tmp_path):
    """debian/sparky-lean-retired-stereo-imports, the file a recipe writes: read once by lean.debhelper."""
    declared = tmp_path / linkcheck.RETIRED_FILE
    declared.parent.mkdir()
    assert linkcheck.declared_retirements(tmp_path) == {}
    declared.write_text(f'# moved by design\nstereo_declare_x11  {REASON}\n')
    assert linkcheck.declared_retirements(tmp_path) == {'stereo_declare_x11': REASON}
    for text, message in (('stereo_declare_x11\n', 'its symbol, white space and the reason'),
                          (f'stereo_declare_x11 {REASON}\nstereo_declare_x11 {REASON}\n', 'once'),
                          (f'printf {REASON}\n', 'is not the name of a stereo symbol'),
                          ('# nothing\n', 'declares nothing')):
        declared.write_text(text)
        with pytest.raises(package.Invalid, match=message):
            linkcheck.declared_retirements(tmp_path)


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
