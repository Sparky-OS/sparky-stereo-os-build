"""The headset side of the rig: a host for a second btvirt server device, over H:4 on its Unix socket.

It makes the device connectable and accepts every ACL and synchronous connection (CVSD, 0x0060), and
answers pairing requests without a key, so a SCO link can be opened from the clone. No kernel
controller is involved, so nothing depends on hci_vhci's one-second creation window.

usage (in the guest): python3 -I headset_host.py BTVIRT_SOCKET ADDRESS_FILE LOG
Writes the device's address, as hciconfig prints addresses, to ADDRESS_FILE once it accepts pages.
"""
import socket
import struct
import sys


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError("btvirt closed the socket")
        data += chunk
    return data


def read_packet(sock):
    kind = recv_exact(sock, 1)[0]
    if kind == 0x04:
        head = recv_exact(sock, 2)
        return kind, head[0], recv_exact(sock, head[1])
    if kind == 0x02:
        head = recv_exact(sock, 4)
        return kind, None, recv_exact(sock, struct.unpack_from("<H", head, 2)[0])
    if kind == 0x03:
        head = recv_exact(sock, 3)
        return kind, None, recv_exact(sock, head[2])
    raise ValueError("unknown H:4 packet type 0x%02x" % kind)


def main():
    path, addr_file, log_path = sys.argv[1:4]
    log = open(log_path, "a")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)

    def send(opcode, params=b""):
        sock.sendall(struct.pack("<BHB", 0x01, opcode, len(params)) + params)

    def command(opcode, params=b""):
        send(opcode, params)
        while True:
            kind, code, data = read_packet(sock)
            if kind == 0x04 and code == 0x0E and struct.unpack_from("<H", data, 1)[0] == opcode:
                return data[3:]

    command(0x0C03)
    raw = command(0x1009)[1:7]
    command(0x0C1A, b"\x02")
    address = ":".join("%02X" % b for b in reversed(raw))
    with open(addr_file, "w") as fh:
        fh.write(address + "\n")
    log.write("headset %s accepts pages\n" % address)
    log.flush()

    while True:
        kind, code, data = read_packet(sock)
        if kind != 0x04:
            continue
        bdaddr = data[:6]
        if code == 0x04:
            link_type = data[9]
            log.write("connection request, link type %d\n" % link_type)
            if link_type == 0x01:
                send(0x0409, bdaddr + b"\x01")
            else:
                send(0x0429, bdaddr + struct.pack("<IIHHBH", 0x1F40, 0x1F40, 0xFFFF, 0x0060, 0xFF, 0x003F))
        elif code == 0x17:
            send(0x040C, bdaddr)
        elif code == 0x16:
            send(0x040E, bdaddr)
        elif code == 0x31:
            send(0x042B, bdaddr + b"\x03\x00\x00")
        elif code == 0x33:
            send(0x042C, bdaddr)
        elif code in (0x03, 0x2C):
            log.write("%s complete, status 0x%02x\n" % ("connection" if code == 0x03 else "synchronous connection", data[0]))
        log.flush()


if __name__ == "__main__":
    main()
