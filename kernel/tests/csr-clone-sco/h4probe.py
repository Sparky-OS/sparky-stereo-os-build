"""Reset a btvirt server device (H:4 over a Unix socket), then ask for its version and buffer sizes.

usage: python3 -I h4probe.py SOCKET_PATH
Prints one line: hci_ver hci_rev lmp_subver manufacturer sco_mtu sco_pkts.
"""
import socket
import struct
import sys


def command(sock, opcode):
    sock.sendall(bytes([0x01]) + struct.pack("<HB", opcode, 0))
    while True:
        head = sock.recv(3)
        if len(head) < 3 or head[0] != 0x04:
            raise SystemExit("unexpected packet %r" % head)
        plen = head[2]
        data = b""
        while len(data) < plen:
            data += sock.recv(plen - len(data))
        if head[1] == 0x0E and struct.unpack_from("<H", data, 1)[0] == opcode:
            return data[3:]


def main():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sys.argv[1])
    command(sock, 0x0C03)  # HCI_Reset first, as the kernel's init does
    ver = command(sock, 0x1001)
    status, hci_ver, hci_rev, lmp_ver, manufacturer, lmp_subver = struct.unpack("<BBHBHH", ver)
    rbs = command(sock, 0x1005)
    status2, acl_mtu, sco_mtu, acl_pkts, sco_pkts = struct.unpack("<BHBHH", rbs)
    print("hci_ver=%d hci_rev=0x%04x lmp_subver=0x%04x manufacturer=%d sco_mtu=%d sco_pkts=%d"
          % (hci_ver, hci_rev, lmp_subver, manufacturer, sco_mtu, sco_pkts))


if __name__ == "__main__":
    main()
