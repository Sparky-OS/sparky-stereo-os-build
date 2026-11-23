#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Fixture test of bin/dpkg-stereo-read-count (ORDER 845): a fake root with three records and a trace whose totals
are known by hand; the red control puts a wrong record in and the same checks must then fail.
Usage: read-count-test.py [WORKDIR]   (prints rows: expected and found; exit 0 only when all pass and the control fails)"""
import importlib.machinery, importlib.util, json, os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader('rc', os.path.join(HERE, '..', 'bin', 'dpkg-stereo-read-count'))
spec = importlib.util.spec_from_loader('rc', loader); rc = importlib.util.module_from_spec(spec); loader.exec_module(rc)


def w(root, path, data):
    p = os.path.join(root, path.lstrip('/')); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(data)


def build(root, hr_a=160):
    a = b'#!/bin/sh\n' + b'a' * 86 + b'\n' * 4                              # 100 bytes, 5 lines
    assert len(a) == 100 and a.count(b'\n') == 5, (len(a), a.count(b'\n'))
    w(root, '/usr/bin/a', a)
    w(root, '/usr/share/doc/pkga/hr/usr/bin/a', b'z' * 150 + b'\n' * 9 + b'z' * 1)  # 160 bytes, 9 lines
    w(root, '/etc/b.conf', b'k=v\n' * 12 + b'\n' * 2)                       # 50 bytes
    w(root, '/usr/lib/c.py', b'c' * 29 + b'\n')                              # 30 bytes
    w(root, '/var/x', b'x' * 10)
    w(root, '/usr/share/stale', b's' * 70)
    os.makedirs(os.path.join(root, 'usr/bin'), exist_ok=True)
    os.symlink('usr/bin', os.path.join(root, 'bin'))
    lc = os.path.join(root, 'usr/share/dpkg-stereo/lc')
    os.makedirs(lc + '/pkga'); os.makedirs(lc + '/pkgc'); os.makedirs(lc + '/pkgs')
    json.dump(dict(package='pkga', architecture='all', files=[dict(path='/usr/bin/a', status='projected', bytes=100, bytes_hr=hr_a, handler='shell', kind='file')]), open(lc + '/pkga/all.json', 'w'))
    json.dump(dict(package='pkgc', architecture='all', files=[dict(path='/usr/lib/c.py', status='unchanged', bytes=30, handler='python', kind='file')]), open(lc + '/pkgc/all.json', 'w'))
    json.dump(dict(package='pkgs', architecture='all', files=[dict(path='/usr/share/stale', status='projected', bytes=80, bytes_hr=120, handler='ini', kind='file')]), open(lc + '/pkgs/all.json', 'w'))
    rd = os.path.join(root, 'var/lib/dpkg-stereo/records'); os.makedirs(rd)
    open(rd + '/pkgb.tsv', 'w').write('#path\tpackage\tversion\tconffile\tsha_orig\tmd5_orig\tsha_lean\thandler\tvariant\tbytes_orig\tbytes_lean\n'
                                      '/etc/b.conf\tpkgb\t1\t1\t0\t0\t0\tini\t\t90\t50\n')
    os.makedirs(os.path.join(root, 'var/lib/dpkg/info'))
    open(os.path.join(root, 'var/lib/dpkg/info/pkgc.list'), 'w').write('/usr/lib/c.py\n')


TRACE = '''\
100   openat(AT_FDCWD, "/usr/bin/a", O_RDONLY|O_CLOEXEC) = 3</usr/bin/a>
100   read(3</usr/bin/a>, "..."..., 60) = 60
[pid 100] read(3</usr/bin/a>, "..."..., 4096) = 40
100   read(3</usr/bin/a>, "", 4096) = 0
100   close(3</usr/bin/a>) = 0
101   openat(AT_FDCWD, "/bin/a", O_RDONLY) = 4</bin/a>
101   read(4</bin/a>, "..."..., 4096) = <unfinished ...>
101   <... read resumed>"...", 4096) = 100
101   close(4</bin/a>) = 0
102   openat(AT_FDCWD, "/etc/b.conf", O_RDONLY) = 5</etc/b.conf>
102   read(5</etc/b.conf>, "..."..., 20) = 20
102   close(5</etc/b.conf>) = 0
103   openat(AT_FDCWD, "/usr/bin/a", O_RDONLY) = 6</usr/bin/a>
103   close(6</usr/bin/a>) = 0
104   openat(AT_FDCWD, "/usr/lib/c.py", O_RDONLY) = 7</usr/lib/c.py>
104   read(7</usr/lib/c.py>, "..."..., 4096) = 30
104   close(7</usr/lib/c.py>) = 0
105   openat(AT_FDCWD, "/var/x", O_RDONLY) = 8</var/x>
105   read(8</var/x>, "..."..., 4096) = 10
105   close(8</var/x>) = 0
106   openat(AT_FDCWD, "/usr/share/stale", O_RDONLY) = 9</usr/share/stale>
106   read(9</usr/share/stale>, "..."..., 4096) = 70
106   close(9</usr/share/stale>) = 0
107   openat(AT_FDCWD, "/proc/meminfo", O_RDONLY) = 10</proc/meminfo>
107   read(10</proc/meminfo>, "..."..., 4096) = 5
107   close(10</proc/meminfo>) = 0
108   openat(AT_FDCWD, "/usr/bin/a", O_RDONLY) = 11</usr/bin/a>
108   mmap(NULL, 100, PROT_READ, MAP_PRIVATE, 11</usr/bin/a>, 0) = 0x7f0000000000
108   close(11</usr/bin/a>) = 0
109   +++ exited with 0 +++
'''
EXPECT = dict(opens=9, projected_opens=5, opened_not_read=1, partial_opens=1, saved_bytes=196, saved_bytes_partial_estimate=16,
              saved_lines=12, lines_unknown_opens=1, bytes_read=335, mapped=100)
UNATT = {'virtual (/proc /sys /dev /run)': (1, 5), 'not owned by any package (generated, data, home, temp)': (1, 10),
         'stale: the file is not the size its record says (replaced since)': (1, 70)}


def run(root, tmp, label):
    tr = os.path.join(tmp, label + '.trace'); open(tr, 'w').write(TRACE)
    js = os.path.join(tmp, label + '.json')
    rc.main(['--root', root, '--strace', tr, '--json', js])
    d = json.load(open(js))
    rows = []
    for k, v in EXPECT.items():
        rows.append((k, v, d['totals'].get(k, 0)))
    for k, (o, b) in UNATT.items():
        rows.append(('unattributed opens: ' + k[:20], o, d['unattributed'].get(k, {}).get('opens', 0)))
        rows.append(('unattributed bytes: ' + k[:20], b, d['unattributed'].get(k, {}).get('bytes_read', 0)))
    rows.append(('package pkga saved_bytes', 180, d['by_package'].get('pkga', {}).get('saved_bytes', 0)))
    rows.append(('handler shell saved_bytes', 180, d['by_handler'].get('shell', {}).get('saved_bytes', 0)))
    # --paths mode: assumed whole, one open of a (100 -> 160), one of b.conf (50 -> 90)
    pl = os.path.join(tmp, label + '.paths'); open(pl, 'w').write('2 /usr/bin/a\n/etc/b.conf\t1\nfoo(12): O /bin/a\n')
    js2 = os.path.join(tmp, label + '-p.json'); rc.main(['--root', root, '--paths', pl, '--json', js2])
    d2 = json.load(open(js2))
    rows.append(('paths mode saved_bytes (3 x 60 + 1 x 40)', 220, d2['totals'].get('saved_bytes', 0)))
    return rows


def show(rows, quiet=False):
    bad = 0
    for name, exp, got in rows:
        ok = exp == got; bad += not ok
        if not quiet: print(f'{"PASS" if ok else "FAIL"}  {name:60} expected {exp:>8} found {got:>8}')
    return bad


def main():
    tmp = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix='rc-test-')
    shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
    good = os.path.join(tmp, 'good'); build(good)
    print('== green: the fixture as built'); bad = show(run(good, tmp, 'good'))
    wrong = os.path.join(tmp, 'wrong'); build(wrong, hr_a=170)   # a wrong record: bytes_hr 170 instead of 160
    print('== red control: a wrong record (bytes_hr 170) must fail these checks'); cbad = show(run(wrong, tmp, 'wrong'), quiet=True)
    print(f'{"PASS" if cbad else "FAIL"}  red control: {cbad} checks failed on the wrong record (must be more than 0)')
    sys.exit(0 if bad == 0 and cbad > 0 else 1)


main()
