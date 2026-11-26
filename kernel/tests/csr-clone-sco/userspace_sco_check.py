"""Check btvirt's server devices and headset_host.py without a kernel: page the headset and set up a CVSD link.

usage: python3 -I userspace_sco_check.py BTVIRT_SOCKET HEADSET_ADDRESS
Prints the Connection Complete and Synchronous Connection Complete it gets (status, link type, air mode).
"""
import socket
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from headset_host import read_packet  # noqa: E402


def main():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sys.argv[1])
    bdaddr = bytes(int(x, 16) for x in reversed(sys.argv[2].split(":")))

    def send(opcode, params=b""):
        sock.sendall(struct.pack("<BHB", 0x01, opcode, len(params)) + params)

    send(0x0C03)
    send(0x0405, bdaddr + struct.pack("<HBBHB", 0xCC18, 0x02, 0x00, 0x0000, 0x01))
    handle = None
    while True:
        kind, code, data = read_packet(sock)
        if kind != 0x04:
            continue
        if code == 0x03:
            status, handle = data[0], struct.unpack_from("<H", data, 1)[0]
            print("connection complete status=0x%02x handle=0x%04x link_type=%d" % (status, handle, data[9]))
            if status:
                return
            send(0x0428, struct.pack("<HIIHHBH", handle, 0x1F40, 0x1F40, 0xFFFF, 0x0060, 0xFF, 0x003F))
        elif code == 0x2C:
            print("synchronous connection complete status=0x%02x link_type=%d air_mode=%d" % (data[0], data[9], data[16]))
            return


if __name__ == "__main__":
    main()
