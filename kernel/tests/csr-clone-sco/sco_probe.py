"""Open a SCO link from a local controller to a remote address and report what the kernel did.

usage (in the guest, as root): python3 -I sco_probe.py FROM_ADDR TO_ADDR
A SCO socket bound to FROM_ADDR connects to TO_ADDR with the default voice setting (0x0060).
Prints one line: connect=ok mtu=N, or connect=ERRNO_NAME, or connect=TIMEOUT.
"""
import errno
import select
import socket
import struct
import sys
import time

SOL_SCO, SCO_OPTIONS = 17, 1


def main():
    src, dst = sys.argv[1], sys.argv[2]
    sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_SCO)
    sock.bind(src)
    sock.setblocking(False)
    try:
        sock.connect(dst)
    except BlockingIOError:
        pass
    except OSError as err:
        print("connect=%s" % errno.errorcode.get(err.errno, err.errno), flush=True)
        return
    _, writable, _ = select.select([], [sock], [], 60)
    err = sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
    if err or not writable:
        print("connect=%s" % (errno.errorcode.get(err, err) if err else "TIMEOUT"), flush=True)
        return
    mtu = struct.unpack("<H", sock.getsockopt(SOL_SCO, SCO_OPTIONS, 2))[0]
    print("connect=ok mtu=%d" % mtu, flush=True)
    time.sleep(3)
    sock.close()


if __name__ == "__main__":
    main()
