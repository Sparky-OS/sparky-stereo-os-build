#!/usr/bin/python3
"""Qualification survey: project every file every installed package owns, with the consumer checks,
writing nothing, and report what each handler does (projected, unchanged, left alone and why).
Run inside the system to survey (a chroot of an image), where its own consumers do the checks.
Usage: survey.py OUT.tsv [JOBS]"""

import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.environ.get('LEAN_LIB', os.path.join(os.path.dirname(__file__), '..', '..')))
from lean import project  # noqa: E402


def owned():
    out = {}
    info = '/var/lib/dpkg/info'
    for f in sorted(os.listdir(info)):
        if f.endswith('.list'):
            pkg = f[:-5]
            for line in open(os.path.join(info, f), errors='surrogateescape'):
                p = line.rstrip('\n')
                if p:
                    out.setdefault(p, pkg)
    return out


def work(item):
    path, pkg = item
    try:
        if not os.path.isfile(path) or os.path.islink(path):
            return None
        st = os.stat(path)
        if st.st_size == 0 or st.st_size > (4 << 20):
            return None
        with open(path, 'rb') as f:
            data = f.read()
        if b'\0' in data[:8192]:
            return None
        t0 = time.perf_counter()
        r = project.project(path, data, pkg.split(':')[0])
        dt = time.perf_counter() - t0
        if r.handler == '' and r.reason == 'no qualified adapter for this consumer':
            return None
        return (path, pkg, r.handler, r.variant, r.status, r.reason.replace('\t', ' ').replace('\n', ' '), r.bytes_in,
                r.bytes_out or r.bytes_in, r.comments_removed, r.check.replace('\t', ' '), round(dt, 4))
    except Exception as e:
        return (path, pkg, '', '', 'error', f'{type(e).__name__}: {e}'.replace('\t', ' ').replace('\n', ' '),
                0, 0, 0, '', 0)


def main():
    out = sys.argv[1]
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    items = sorted(owned().items())
    t0 = time.time()
    n = 0
    with open(out, 'w') as f, ProcessPoolExecutor(jobs) as ex:
        f.write('path\tpackage\thandler\tvariant\tstatus\treason\tbytes\tlean_bytes\tcomments\tcheck\tseconds\n')
        for row in ex.map(work, items, chunksize=32):
            if row:
                f.write('\t'.join(str(x) for x in row) + '\n')
                n += 1
    print(f'{n} files surveyed in {time.time() - t0:.0f} s')


if __name__ == '__main__':
    main()
