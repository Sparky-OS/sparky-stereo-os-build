"""A USB Bluetooth device on dummy_hcd through FunctionFS, whose controller is a btvirt server device.

The device has the CSR id 0a12:0001 and the bcdDevice given, so btusb binds it as BTUSB_CSR and runs
btusb_setup_csr(). Its first interface carries HCI as the USB transport does: commands in class
requests on endpoint 0, events on an interrupt IN endpoint, ACL data on bulk endpoints. Its second
interface (the isochronous one) has alternate setting 0 only; btusb claims it, and the alternate
setting btusb asks for when a SCO link comes up shows in its log. SCO data is not carried.

usage (in the guest, as root): python3 -I ffs_clone.py FFS_DIR BTVIRT_SOCKET LOG
FFS_DIR is a functionfs mount of an instance already linked into a gadget configuration; the caller
binds the gadget to the UDC once this program prints "descriptors written".
"""
import os
import queue
import socket
import struct
import sys
import threading

EV_BIND, EV_UNBIND, EV_ENABLE, EV_DISABLE, EV_SETUP, EV_SUSPEND, EV_RESUME = range(7)
EV_NAMES = ["bind", "unbind", "enable", "disable", "setup", "suspend", "resume"]

enabled = threading.Event()
log_lock = threading.Lock()
log_file = None


def log(text):
    with log_lock:
        log_file.write(text + "\n")
        log_file.flush()


def interface(number, endpoints):
    return struct.pack("<BBBBBBBBB", 9, 4, number, 0, endpoints, 0xE0, 0x01, 0x01, 0)


def endpoint(address, attributes, max_packet, interval):
    return struct.pack("<BBBBHB", 7, 5, address, attributes, max_packet, interval)


def descriptors():
    """Full speed, as the clone: interrupt 0x81 (16), bulk 0x02 and 0x82 (64); interface 1 empty."""
    body = (interface(0, 3) + endpoint(0x81, 0x03, 16, 1) + endpoint(0x02, 0x02, 64, 0)
            + endpoint(0x82, 0x02, 64, 0) + interface(1, 0))
    flags = 1 | 64  # FUNCTIONFS_HAS_FS_DESC | FUNCTIONFS_ALL_CTRL_RECIP
    return struct.pack("<IIII", 3, 16 + len(body), flags, 5) + body


def strings():
    return struct.pack("<IIII", 2, 16, 0, 0)


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError("btvirt closed the socket")
        data += chunk
    return data


def from_controller(sock, events, acl):
    """Read H:4 packets from btvirt: events to the interrupt endpoint, ACL to bulk IN."""
    while True:
        kind = recv_exact(sock, 1)[0]
        if kind == 0x04:
            head = recv_exact(sock, 2)
            pkt = head + recv_exact(sock, head[1])
            if head[0] == 0x0E and len(pkt) >= 5:
                log("event 0x0e command complete opcode 0x%04x status 0x%02x"
                    % (struct.unpack_from("<H", pkt, 3)[0], pkt[5] if len(pkt) > 5 else 0))
            elif head[0] == 0x0F:
                log("event 0x0f command status opcode 0x%04x status 0x%02x"
                    % (struct.unpack_from("<H", pkt, 4)[0], pkt[2]))
            else:
                log("event 0x%02x len %d" % (head[0], head[1]))
            events.put(pkt)
        elif kind == 0x02:
            head = recv_exact(sock, 4)
            acl.put(head + recv_exact(sock, struct.unpack_from("<H", head, 2)[0]))
        elif kind == 0x03:
            head = recv_exact(sock, 3)
            recv_exact(sock, head[2])
            log("sco data from the controller dropped (no isochronous transport)")
        elif kind == 0x05:
            head = recv_exact(sock, 4)
            recv_exact(sock, struct.unpack_from("<H", head, 2)[0] & 0x3FFF)
        else:
            raise ValueError("unknown H:4 packet type 0x%02x" % kind)


def writer(path, packets, name):
    fd = os.open(path, os.O_RDWR)
    while True:
        pkt = packets.get()
        while True:
            enabled.wait()
            try:
                os.write(fd, pkt)
                break
            except OSError as err:
                log("%s write: %s, retrying when enabled" % (name, err))
                enabled.clear()


def bulk_out(path, sock):
    fd = os.open(path, os.O_RDWR)
    while True:
        enabled.wait()
        try:
            data = os.read(fd, 4096)
        except OSError as err:
            log("bulk out read: %s" % err)
            enabled.clear()
            continue
        if data:
            sock.sendall(b"\x02" + data)


def main():
    global log_file
    ffs, sock_path, log_path = sys.argv[1:4]
    log_file = open(log_path, "a")
    ep0 = os.open(os.path.join(ffs, "ep0"), os.O_RDWR)
    os.write(ep0, descriptors())
    os.write(ep0, strings())
    print("descriptors written", flush=True)
    log("descriptors written")

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)
    events, acl = queue.Queue(), queue.Queue()
    for target, args in ((from_controller, (sock, events, acl)),
                         (writer, (os.path.join(ffs, "ep1"), events, "interrupt")),
                         (writer, (os.path.join(ffs, "ep3"), acl, "bulk in")),
                         (bulk_out, (os.path.join(ffs, "ep2"), sock))):
        threading.Thread(target=target, args=args, daemon=True).start()

    while True:
        raw = os.read(ep0, 12 * 8)
        for off in range(0, len(raw), 12):
            setup, kind = raw[off:off + 8], raw[off + 8]
            if kind != EV_SETUP:
                log("ffs event %s" % (EV_NAMES[kind] if kind < len(EV_NAMES) else kind))
                if kind in (EV_ENABLE, EV_RESUME):
                    enabled.set()
                elif kind in (EV_DISABLE, EV_SUSPEND, EV_UNBIND):
                    enabled.clear()
                continue
            req_type, req, value, index, length = struct.unpack("<BBHHH", setup)
            if req_type == 0x20 and req == 0 and length >= 3:
                cmd = os.read(ep0, length)
                log("command 0x%04x len %d" % (struct.unpack_from("<H", cmd)[0], length))
                sock.sendall(b"\x01" + cmd)
            else:
                log("setup %02x %02x %04x %04x %d: stalled" % (req_type, req, value, index, length))
                try:
                    if req_type & 0x80:
                        os.read(ep0, 0)
                    else:
                        os.write(ep0, b"")
                except OSError:
                    pass


if __name__ == "__main__":
    main()
