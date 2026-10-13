# SPDX-License-Identifier: GPL-2.0-or-later
"""Bounded immutable frame transport. No message contains executable content."""
import array
import fcntl
import os
import socket
import stat
import struct
from dataclasses import dataclass

HEADER = struct.Struct('<4s7I')
SEALS = fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL


@dataclass
class Frame:
    fd: int
    width: int
    height: int
    sequence: int

    def close(self):
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1

    def header(self):
        return HEADER.pack(b'SD3F', 1, self.width, self.height, self.width * 4,
                           self.sequence, self.width * self.height * 4, 1)


def receive(channel, last=0):
    data, controls, flags, _ = channel.recvmsg(HEADER.size, socket.CMSG_SPACE(16 * 4), socket.MSG_CMSG_CLOEXEC)
    descriptors = []
    try:
        for level, kind, payload in controls:
            if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                values = array.array('i')
                values.frombytes(payload[:len(payload) - len(payload) % values.itemsize])
                descriptors.extend(values)
        if not data:
            raise EOFError('producer closed')
        if flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC) or len(data) != HEADER.size or len(descriptors) != 1:
            raise ValueError('invalid frame envelope')
        magic, version, width, height, stride, sequence, size, format_ = HEADER.unpack(data)
        if (magic != b'SD3F' or version != 1 or format_ != 1 or
                not 2 <= width <= 8192 or width % 2 or not 1 <= height <= 4096 or
                stride != width * 4 or size != stride * height or size > 67108864 or sequence <= last):
            raise ValueError('invalid frame dimensions, format or sequence')
        descriptor = descriptors[0]
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size != size or info.st_uid != os.getuid():
            raise ValueError('invalid frame storage')
        if fcntl.fcntl(descriptor, fcntl.F_GET_SEALS) & SEALS != SEALS:
            raise ValueError('frame is mutable')
        descriptors.pop()
        return Frame(descriptor, width, height, sequence)
    finally:
        for descriptor in descriptors:
            os.close(descriptor)


def send(channel, frame):
    channel.sendmsg([frame.header()], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [frame.fd]))])


def acknowledge(channel, frame):
    channel.send(struct.pack('<I', frame.sequence))


def relay(source, consumer, timeout=1.0):
    """A separate broker validates both directions and allows one outstanding frame."""
    source.settimeout(timeout)
    consumer.settimeout(timeout)
    last = 0
    while True:
        try:
            frame = receive(source, last)
        except EOFError:
            return
        try:
            send(consumer, frame)
            ack = consumer.recv(5)
            if ack != struct.pack('<I', frame.sequence):
                raise ValueError('invalid consumer acknowledgement')
            acknowledge(source, frame)
            last = frame.sequence
        finally:
            frame.close()


if __name__ == '__main__':
    import sys
    if len(sys.argv) != 3:
        raise SystemExit('usage: frames.py PRODUCER_FD CONSUMER_FD')
    with socket.socket(fileno=int(sys.argv[1])) as producer, socket.socket(fileno=int(sys.argv[2])) as consumer:
        try:
            relay(producer, consumer)
        except (OSError, ValueError) as error:
            print(f'frame broker stopped: {error}', file=sys.stderr)
            raise SystemExit(1)
