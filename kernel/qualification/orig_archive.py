# SPDX-License-Identifier: GPL-2.0-only
"""Pack a prepared kernel source tree (without debian/) into its orig archive: the same tree gives the same bytes (ORDER 636).

    pack(SOURCE_DIR, ARCHIVE, TOP, STAMP)

Before build 18 the archive took each file's own time, owner and order from the export, so a tree restored or exported
again gave another orig (build 17's rt: the same tree, another .dsc). Here every member is sorted by name, dated STAMP
(the recipe's date, the SOURCE_DATE_EPOCH the source package uses), owned by 0:0 numerically, without group or other
write bits (a umask of 002 or 022 gives the same modes), in GNU format, under the top directory TOP; xz keeps its
preset and its multi-threaded mode on every processor this process may use (ORDER 638): that mode splits the stream into
the same blocks whatever the number of threads (-T+N; plain -T1 would be the single-threaded format).
"""
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os'))
from lean import parallel

TAR_OPTIONS = ['--sort=name', '--owner=0', '--group=0', '--numeric-owner', '--mode=go-w', '--format=gnu']


def pack(source, archive, top, stamp):
    started, threads = time.monotonic(), parallel.processors()
    with open(archive, 'wb') as sink:
        packed = subprocess.Popen(['tar', '-C', str(source), '--exclude=./debian', *TAR_OPTIONS, f'--mtime=@{int(stamp)}',
                                   '--transform=flags=r;s,^\\.,' + top + ',', '-cf', '-', '.'], stdout=subprocess.PIPE)
        compressed = subprocess.Popen(['xz', f'-T+{threads}', '-3'], stdin=packed.stdout, stdout=sink)
        packed.stdout.close()
        if compressed.wait() != 0 or packed.wait() != 0:
            raise SystemExit(f'orig_archive: packing {source} into {archive} failed')
    print(f'orig: {Path(archive).name} packed in {time.monotonic() - started:.0f} s on {threads} processors')
