# SPDX-License-Identifier: GPL-2.0-or-later
"""Session-side prototype; control comes from Plasma, pixels go to the greeter."""
import json
import os
from pathlib import Path
import selectors
import select
import signal
import socket
import struct
import subprocess
import sys
import time
from catalogue import Rotation, active, load
from frames import receive, send
from preferences import disabled_savers

def read_display(fd, timeout=5):
    deadline = time.monotonic() + timeout
    data = b''
    while len(data) < 16:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            raise RuntimeError('private display did not start')
        byte = os.read(fd, 1)
        if byte == b'\n':
            if data and data.isdigit(): return ':' + data.decode('ascii')
            break
        if not byte: break
        data += byte
    raise RuntimeError('invalid private display')

class Controller:
    def __init__(self, catalogue, control, consumer):
        self.rotation = Rotation(load(catalogue))
        self.control, self.consumer = control, consumer
        self.state = dict(locked=False, display_on=False, on_ac=False)
        self.process = self.source = self.entry = None
        self.pending = None
        self.sequence = 0
        self.started = time.monotonic()
        self.source_sequence = 0
        self.selector = selectors.DefaultSelector()
        self.selector.register(control, selectors.EVENT_READ, 'control')
        self.selector.register(consumer, selectors.EVENT_READ, 'consumer')
        read, write = os.pipe()
        self.xvfb = subprocess.Popen(['Xvfb','-displayfd',str(write),'-screen','0','2560x1440x24','-ac','-nolisten','tcp'],
                                     pass_fds=(write,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write)
        try:
            self.display = read_display(read)
        except Exception:
            self.xvfb.terminate(); self.xvfb.wait(timeout=3)
            raise
        finally:
            os.close(read)

    def watch_source(self):
        if self.source and self.pending is None:
            try: self.selector.register(self.source, selectors.EVENT_READ, 'source')
            except KeyError: pass

    def stop(self):
        if self.source:
            try: self.selector.unregister(self.source)
            except KeyError: pass
            self.source.close(); self.source = None
        if self.process:
            try: os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL); self.process.wait()
            self.process = None

    def start(self):
        if not active(self.state): return
        self.entry = self.rotation.next(disabled_savers())
        if not self.entry: return
        self.source, writer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        env = os.environ.copy()
        for key in list(env):
            if key.startswith('GL_STEREO') or key in ('LD_PRELOAD','DISPLAY','WAYLAND_DISPLAY','XAUTHORITY'):
                env.pop(key)
        env.update(self.entry['environment'])
        env['PATH'] = '/usr/libexec/xscreensaver:' + env.get('PATH', os.defpath)
        env.update(DISPLAY=self.display, GL_STEREO_FRAME_FD=str(writer.fileno()))
        try:
            announce = Path(__file__).resolve().with_name('announce')
            self.process = subprocess.Popen([str(announce),*self.entry['command']], env=env,
                                           pass_fds=(writer.fileno(),), start_new_session=True,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            writer.close()
        self.started = time.monotonic()
        self.source_sequence = 0
        self.watch_source()
        print('started',self.entry['id'],flush=True)

    def run(self):
        try:
            while True:
                for key, _ in self.selector.select(.1):
                    if key.data == 'control':
                        data, _, flags, _ = self.control.recvmsg(256)
                        if not data: return
                        if flags & socket.MSG_TRUNC: raise ValueError('oversized control message')
                        message = json.loads(data)
                        if message == {'event':'shutdown'}: return
                        if message == {'event':'rotate'}:
                            self.stop(); self.start()
                        elif (set(message) == {'locked','display_on','on_ac'} and
                              all(type(value) is bool for value in message.values())):
                            self.state = message
                            if not active(self.state): self.stop()
                            elif not self.process: self.start()
                        else:
                            raise ValueError('invalid control message')
                    elif key.data == 'source' and key.fileobj is self.source and self.pending is None:
                        try:
                            frame = receive(self.source, self.source_sequence)
                        except (EOFError, ValueError, OSError):
                            self.rotation.exclude(self.entry['id']); self.stop(); self.start(); continue
                        original = frame.sequence
                        self.source_sequence = original
                        self.sequence += 1; frame.sequence = self.sequence
                        try: send(self.consumer,frame)
                        finally: frame.close()
                        self.pending = (self.sequence, original, self.source, time.monotonic())
                        self.selector.unregister(self.source)
                    elif key.data == 'consumer':
                        ack = self.consumer.recv(5)
                        if not ack: return
                        if self.pending is None or ack != struct.pack('<I',self.pending[0]):
                            raise ValueError('invalid frame acknowledgement')
                        if self.pending[2] is self.source:
                            self.source.send(struct.pack('<I',self.pending[1]))
                        self.pending = None
                        self.started = time.monotonic()
                        self.watch_source()
                if self.pending and time.monotonic() - self.pending[3] > 2:
                    raise TimeoutError('consumer stalled')
                if self.process and self.pending is None and (self.process.poll() is not None or time.monotonic()-self.started > 5):
                    self.rotation.exclude(self.entry['id']); self.stop(); self.start()
        finally:
            self.stop()
            self.selector.close()
            self.xvfb.terminate(); self.xvfb.wait(timeout=3)

if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('usage: controller.py CATALOGUE CONTROL_FD CONSUMER_FD')
    with socket.socket(fileno=int(sys.argv[2])) as control, socket.socket(fileno=int(sys.argv[3])) as consumer:
        Controller(sys.argv[1],control,consumer).run()
