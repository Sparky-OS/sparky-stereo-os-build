# SPDX-License-Identifier: GPL-2.0-or-later
import array
import fcntl
import os
from pathlib import Path
import socket
import struct
import sys
sys.path.insert(0, str(Path('savers').resolve()))
from frames import HEADER, SEALS, receive

def memory(size=32, sealed=True):
    fd = os.memfd_create('test-frame', os.MFD_ALLOW_SEALING | os.MFD_CLOEXEC)
    os.ftruncate(fd, size)
    if sealed:
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, SEALS)
    return fd

header = HEADER.pack(b'SD3F', 1, 4, 2, 16, 1, 32, 1)
def check(data=header, size=32, sealed=True, count=1, last=0, valid=False):
    before = len(os.listdir('/proc/self/fd'))
    a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    descriptors = [memory(size, sealed) for _ in range(count)]
    try:
        a.sendmsg([data], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', descriptors))])
        try:
            frame = receive(b, last)
        except (ValueError, OSError):
            assert not valid
        else:
            assert valid
            frame.close()
    finally:
        for fd in descriptors:
            os.close(fd)
        a.close(); b.close()
    assert len(os.listdir('/proc/self/fd')) == before

check(valid=True)
check(data=b'bad')
check(data=header + b'trailing')
check(size=33)
check(sealed=False)
check(count=2)
check(count=20)
check(last=1)
check(data=HEADER.pack(b'SD3F', 1, 8192, 4096, 32768, 2, 134217728, 1))
check(data=HEADER.pack(b'SD3F', 1, 3, 2, 12, 2, 24, 1), size=24)
check(data=HEADER.pack(b'SD3F', 1, 4, 2, 16, 2, 32, 99))
print('PASS: frame bounds, seals, replay, malformed messages, truncated/multiple descriptors and no descriptor leaks')
