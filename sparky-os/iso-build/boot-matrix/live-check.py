#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
"""live-check.py : boot an ISO (or an installed disk) headless through its firmware, its own boot menu and its own
kernel, log in on the serial line and run checks, with screenshots along the way.

  live-check.py --iso FILE --fw CASE --media cd|usb --out DIR [--vars VARS.fd] [--disk RAW] [--keys STEPS]
                [--user live --password live] [--cmds FILE] [--login-wait 600] [--desktop-wait 60]

The machine starts with bootmatrix.py (QEMU, -display none, the QMP and serial sockets in DIR). --keys is a list of
key steps for the boot menus before the system starts, comma separated: a qcode or chord (ret, esc, down, ctrl+x),
"type:TEXT", "slowtype:TEXT" (0.4 s a key: ISOLINUX reads the BIOS keyboard buffer, 15 keys, and loses keys typed
faster while it redraws), "wait:SECONDS", "shot:NAME" or "console"; the default waits for the menu and presses Enter. "console"
edits the selected GRUB entry and starts it: the linux line (the entry's first line, "if linux ...; then") gets
console=ttyS0,115200 console=tty0 before its "; then", so the kernel and a getty speak on the serial line too. Every byte of the serial
line goes to DIR/serial.log; the commands' output to DIR/session.txt. Nothing is shown on any display.
"""
import argparse
import os
import re
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from vmctl import Qmp, keys_for  # noqa: E402

CONSOLE = ' console=ttyS0,115200 console=tty0'


class Serial:
    def __init__(self, path, log):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(300):
            try:
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.1)
        self.s.settimeout(0.5)
        self.buf = b''
        self.log = open(log, 'ab')

    def read(self, sec):
        end = time.time() + sec
        while time.time() < end:
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                return
            if not d:
                return
            self.buf += d
            self.log.write(d)
            self.log.flush()

    def wait_for(self, tokens, sec):
        end = time.time() + sec
        while time.time() < end:
            self.read(1)
            tail = self.buf[-400:]
            if any(t in tail for t in tokens):
                n = len(self.buf)
                self.read(1.5)
                if len(self.buf) == n:
                    return True
        return False

    def send(self, text):
        self.s.sendall(text.encode())


def clean(out):
    out = out.replace('\r', '')
    out = re.sub(r'\x1b\][^\x07\x1b]*(\x07|\x1b\\)', '', out)
    return re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--iso')
    ap.add_argument('--fw', required=True)
    ap.add_argument('--media', default='cd', choices=['cd', 'usb'])
    ap.add_argument('--out', required=True)
    ap.add_argument('--vars')
    ap.add_argument('--disk')
    ap.add_argument('--keys', default='wait:30,shot:menu,ret')
    ap.add_argument('--user', default='live')
    ap.add_argument('--password', default='live')
    ap.add_argument('--cmds')
    ap.add_argument('--login-wait', type=float, default=600)
    ap.add_argument('--desktop-wait', type=float, default=60)
    ap.add_argument('--ram', default='4G')
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    cmd = [sys.executable, os.path.join(HERE, 'bootmatrix.py'), '--fw', a.fw, '--media', a.media, '--out', out,
           '--detach', '--serial-sock', '--keep-vars', '--reboot', '--ram', a.ram]
    cmd += ['--iso', a.iso] if a.iso else []
    cmd += ['--vars', a.vars] if a.vars else []
    cmd += ['--disk', a.disk] if a.disk else []
    if not a.iso:
        sys.exit('--iso is needed (the boot matrix always has a medium; an installed disk boots first with bootindex)')
    t0 = time.time()
    started = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    print(started.strip())
    report = open(os.path.join(out, 'session.txt'), 'w')
    ser = Serial(os.path.join(out, 'serial.sock'), os.path.join(out, 'serial.log'))
    q = Qmp(os.path.join(out, 'qmp.sock'))

    def note(text):
        line = '@ %6.1f s  %s' % (time.time() - t0, text)
        print(line)
        report.write(line + '\n')
        report.flush()

    def shot(name):
        q.cmd('screendump', filename=os.path.join(out, name + '.png'), format='png')
        note('screenshot ' + name + '.png')

    def key(k):
        q.cmd('send-key', keys=[{'type': 'qcode', 'data': x} for x in k.split('+')])

    def typ(text, pause=0.05):
        for ch in text:
            q.cmd('send-key', keys=[{'type': 'qcode', 'data': k} for k in keys_for(ch)])
            time.sleep(pause)

    steps = a.keys.split(',') if a.keys else []
    for st in steps:
        if st.startswith('wait:'):
            ser.read(float(st[5:]))
        elif st.startswith('shot:'):
            shot(st[5:])
        elif st.startswith('type:'):
            typ(st[5:])
        elif st.startswith('slowtype:'):
            typ(st[9:], 0.4)
        else:
            if st == 'console':
                # GRUB's editor shows "setparams '<title>'", an empty line, then the entry: its first line, at its
                # end, before "; then"
                key('e'); ser.read(1.5)
                for k in ('down', 'down', 'ctrl+e'):
                    key(k); time.sleep(0.2)
                for _ in range(6):
                    key('left'); time.sleep(0.1)
                typ(CONSOLE); ser.read(1)
                shot('edited-entry')
                key('ctrl+x')
                note('edited the entry: +' + CONSOLE.strip() + ', started it')
                continue
            key(st)
            note('key ' + st)
            ser.read(1.0)

    if a.cmds:
        cmds = [c for c in open(a.cmds).read().splitlines() if c.strip() and not c.startswith('#')]
        if ser.wait_for([b'login: '], a.login_wait):
            note('login prompt on the serial line')
            ser.read(a.desktop_wait)
            shot('desktop')
            ser.send('\n')
            ser.wait_for([b'login: '], 30)
            ser.send(a.user + '\n')
            ser.wait_for([b'assword: ', b'asswort: ', b'Senha: '], 30)
            ser.send(a.password + '\n')
            ser.read(5)
            ser.send("PROMPT_COMMAND=; export PS1='@@ ' TERM=dumb SYSTEMD_PAGER= PAGER=cat; stty cols 220\n")
            ser.read(2)
            for c in cmds:
                mark = len(ser.buf)
                ser.send(c + "; echo __E''ND__\n")
                end = time.time() + 300
                while time.time() < end and b'__END__\n' not in ser.buf[mark:].replace(b'\r', b''):
                    ser.read(0.5)
                text = clean(ser.buf[mark:].decode(errors='replace'))
                body = text.split('\n', 1)[1] if '\n' in text else text
                report.write('$ ' + c + '\n' + body.split('__END__')[0].rstrip().rstrip('@').rstrip() + '\n\n')
                report.flush()
            shot('after-checks')
        else:
            note('no login prompt on the serial line')
            shot('no-login')
    else:
        ser.read(a.login_wait)
        shot('end')
    q.cmd('quit')
    ser.read(2)
    note('done')


if __name__ == '__main__':
    main()
