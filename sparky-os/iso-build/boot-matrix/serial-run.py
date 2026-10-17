#!/usr/bin/env python3
"""serial-run.py SOCK USER PASSWORD CMD... : logs in on a guest's serial getty (SOCK, QEMU's chardev socket) and runs
each CMD in one shell, printing its output; the last CMD may reboot the guest. Waits for the login prompt to settle
(a getty reprints its banner when it is woken), so the user name is never typed into the banner."""
import socket
import sys
import time


def main():
    sock, user, pw, *cmds = sys.argv[1:]
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(0.5)
    s.connect(sock)
    buf = b""

    def read(sec):
        nonlocal buf
        t = time.time()
        while time.time() - t < sec:
            try:
                d = s.recv(65536)
                if d:
                    buf += d
            except socket.timeout:
                pass

    def wait_for(token, sec):
        t = time.time()
        while time.time() - t < sec:
            read(0.5)
            if buf.rstrip().endswith(token):
                # quiet for a second: the prompt is the last thing written
                n = len(buf)
                read(1.0)
                if len(buf) == n:
                    return True
        return False

    s.sendall(b"\n")
    if not wait_for(b"login:", 60):
        sys.exit("no login prompt")
    s.sendall(user.encode() + b"\n")
    if not wait_for(b"Password:", 20):
        sys.exit("no password prompt")
    s.sendall(pw.encode() + b"\n")
    read(4)
    s.sendall(b"PROMPT_COMMAND=; export PS1='@@ ' TERM=dumb SYSTEMD_PAGER= PAGER=cat; stty cols 200\n")
    read(2)
    for c in cmds:
        buf = b""
        s.sendall(c.encode() + b"; echo __E''ND__\n")
        t = time.time()
        while time.time() - t < 300 and b"__END__\r\n" not in buf:
            read(0.5)
            if b"reboot" in c.encode() and time.time() - t > 5:
                break
        out = buf.decode(errors="replace").replace("\r", "")
        # the shell's OSC 3008 context marks (systemd) and other escape sequences
        import re
        out = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", out)
        out = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", out)
        print("$ " + c)
        print(out.split("\n", 1)[1].split("__END__")[0].rstrip() if "\n" in out else out)
    s.sendall(b"exit\n")
    read(1)
    s.close()


main()
