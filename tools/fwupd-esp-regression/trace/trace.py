#!/usr/bin/python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Temporary system-bus and ESP trace. Never starts fwupd or changes firmware."""
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import selectors
import signal
import socket
import subprocess
import time

BOOT = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
LOG = Path('/var/log/fwupd-esp-unmount-314')
LOG.mkdir(mode=0o700, parents=True, exist_ok=True)
logger = logging.getLogger('order314')
logger.setLevel(logging.INFO)
handler = RotatingFileHandler(LOG / 'trace.jsonl', maxBytes=4*1024*1024, backupCount=2)
logger.addHandler(handler)

def record(event, **fields):
    logger.info(json.dumps(dict(boot=BOOT, realtime=time.time(), monotonic=time.monotonic(),
                                event=event, **fields), sort_keys=True))

def mountinfo():
    return [line for line in Path('/proc/self/mountinfo').read_text().splitlines()
            if line.split()[4] == '/boot/efi']

def snapshot(reason):
    lines = mountinfo()
    record('snapshot', reason=reason, mountinfo=lines)
    return lines

def notify():
    address = os.environ.get('NOTIFY_SOCKET')
    if address:
        if address.startswith('@'):
            address = '\0' + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.sendto(b'READY=1\nSTATUS=Monitoring UDisks and ESP mount state', address)

filters = [
    "type='method_call',interface='org.freedesktop.UDisks2.Filesystem',member='Mount'",
    "type='method_call',interface='org.freedesktop.UDisks2.Filesystem',member='Unmount'",
    "type='error',sender='org.freedesktop.UDisks2'",
    "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.freedesktop.UDisks2.Filesystem'",
    "type='signal',interface='org.freedesktop.login1.Manager',member='SessionNew'",
    "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.fwupd'",
]
monitor = subprocess.Popen(['/usr/bin/stdbuf', '-oL', '/usr/bin/dbus-monitor', '--system', *filters],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
selector = selectors.DefaultSelector()
selector.register(monitor.stdout, selectors.EVENT_READ)
os.set_blocking(monitor.stdout.fileno(), False)
stopping = False

def stop(_signum, _frame):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
buffer = b''
ready = False
started = time.monotonic()
previous = snapshot('boot-service-start')
restore_at = None
attempts = 0
pending = []
try:
    while not stopping:
        now = time.monotonic()
        if monitor.poll() is not None:
            raise RuntimeError(f'dbus-monitor exited {monitor.returncode}')
        if not ready and now - started > 8:
            raise RuntimeError('D-Bus monitor readiness timed out')
        for key, _ in selector.select(timeout=0.2):
            buffer += os.read(key.fileobj.fileno(), 65536)
            while b'\n' in buffer:
                raw, buffer = buffer.split(b'\n', 1)
                line = raw.decode(errors='replace')
                record('dbus', line=line)
                if not ready and 'member=NameLost' in line:
                    ready = True
                    record('ready', monitor_pid=monitor.pid)
                    notify()
                if 'member=SessionNew' in line:
                    snapshot('login-session-new')
                    pending.extend([(now+2, 'login-plus-2s'), (now+10, 'login-plus-10s')])
                if line.startswith('method call ') and ('member=Mount' in line or 'member=Unmount' in line):
                    snapshot('udisks-call')
                    sender = re.search(r'sender=(:[0-9.]+)', line)
                    if sender:
                        result = subprocess.run(['/usr/bin/busctl', '--system', 'call',
                            'org.freedesktop.DBus', '/org/freedesktop/DBus',
                            'org.freedesktop.DBus', 'GetConnectionUnixProcessID', 's', sender[1]],
                            capture_output=True, text=True, timeout=2)
                        record('caller', sender=sender[1], pid_reply=result.stdout.strip(),
                               result=result.returncode)
        for deadline, reason in pending[:]:
            if now >= deadline:
                snapshot(reason)
                pending.remove((deadline, reason))
        current = mountinfo()
        if current != previous:
            snapshot('mount-state-changed')
            if previous and not current and attempts < 3:
                restore_at = now + 3
            previous = current
        if restore_at is not None and now >= restore_at:
            restore_at = None
            if not mountinfo():
                attempts += 1
                record('remount-request', attempt=attempts)
                result = subprocess.run(['/usr/bin/systemctl', 'start', 'boot-efi.mount'],
                                        capture_output=True, text=True, timeout=30)
                restored = snapshot('after-remount')
                record('remount-result', result=result.returncode, stderr=result.stderr,
                       mounted=bool(restored))
                previous = restored
                if not restored and attempts < 3:
                    restore_at = time.monotonic() + 10
finally:
    record('stopping')
    monitor.terminate()
    try:
        monitor.wait(timeout=3)
    except subprocess.TimeoutExpired:
        monitor.kill()
        monitor.wait()
