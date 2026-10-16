#!/usr/bin/env python3
"""session.py : boot a live ISO's kernel headless with a serial console, log in on the serial line and run checks.

  session.py --iso FILE --out DIR [--kernel vmlinuz|vmlinuz2] [--append "..."] [--disk FILE] [--wait 240]
             [--user live --password live] [--cmds FILE] [--shots "60,120"] [--keep]

The kernel and initrd come out of the ISO (xorriso), QEMU boots them with -kernel/-initrd and the ISO as a CD, so
live-boot finds its medium; the firmware boot chain is not part of this check (the boot matrix covers it).
Each line of --cmds is run in the login shell; its output goes to DIR/session.txt. Screenshots by QMP to DIR.
Nothing is shown on any display (-display none).
"""
import argparse, os, re, socket, subprocess, sys, time, json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from vmctl import Qmp  # noqa: E402


def extract(iso, path, dst):
    subprocess.check_call(["docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{os.path.dirname(iso)}:/i:ro",
                           "-v", f"{os.path.dirname(dst)}:/o", "beta-iso-lutz-build:1", "xorriso", "-osirrox", "on", "-indev",
                           "/i/" + os.path.basename(iso), "-extract", path, "/o/" + os.path.basename(dst)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class Serial:
    def __init__(self, path, log):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(200):
            try:
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.1)
        self.s.settimeout(1)
        self.buf = b""
        self.log = open(log, "ab")

    def read(self, t=1.0):
        end = time.time() + t
        while time.time() < end:
            try:
                d = self.s.recv(65536)
                if not d:
                    break
                self.buf += d
                self.log.write(d)
                self.log.flush()
            except socket.timeout:
                pass

    def wait_for(self, token, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if token.encode() in self.buf:
                return True
            self.read(1)
        return False

    def send(self, text):
        self.s.sendall(text.encode())


def run_cmds(a, s, q, out, t0, report):
    s.send(a.user + "\n")
    s.wait_for("assword:", 20)
    s.send(a.password + "\n")
    s.read(4)
    s.send("PROMPT_COMMAND=; PS0=; bind 'set enable-bracketed-paste off'; export PS1='@@ ' TERM=dumb SYSTEMD_PAGER= PAGER=cat; stty cols 200\n")
    s.read(2)
    for line in (open(a.cmds).read().splitlines() if a.cmds else []):
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("@shot "):
            q.cmd("screendump", filename=os.path.join(out, line.split()[1] + ".png"), format="png")
            report.write(f"@ screenshot {line.split()[1]}.png at {time.time() - t0:.0f} s\n\n")
            continue
        s.buf = b""
        s.send(line + "; echo __E''ND__\n")
        s.wait_for("__END__\r\n", 300)
        s.read(0.5)
        text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[a-zA-Z]", "", s.buf.decode(errors="replace")).replace("\r", "")
        text = (text.split("\n", 1)[1] if "\n" in text else text).split("__END__")[0]
        report.write(f"$ {line}\n{text.rstrip()}\n\n")
        report.flush()


def attach(a, out):
    t0 = time.time()
    s = Serial(os.path.join(os.path.abspath(a.attach), "serial.sock"), os.path.join(out, "serial.log"))
    q = Qmp(os.path.join(os.path.abspath(a.attach), "qmp.sock"))
    report = open(os.path.join(out, "session.txt"), "w")
    s.send("\n")
    ok = s.wait_for("login:", a.wait)
    report.write(f"# login prompt after {time.time() - t0:.0f} s: {ok}\n")
    if ok:
        run_cmds(a, s, q, out, t0, report)
    report.write(f"# done after {time.time() - t0:.0f} s\n")
    print(json.dumps({"login": ok, "seconds": round(time.time() - t0)}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--kernel", default="vmlinuz")
    ap.add_argument("--append", default="boot=live components quiet splash")
    ap.add_argument("--disk")
    ap.add_argument("--wait", type=int, default=300)
    ap.add_argument("--user", default="live")
    ap.add_argument("--password", default="live")
    ap.add_argument("--cmds")
    ap.add_argument("--shots", default="")
    ap.add_argument("--extra", default="", help="extra QEMU arguments, space separated")
    ap.add_argument("--keep", action="store_true", help="leave QEMU running at the end")
    ap.add_argument("--attach", help="a running VM's folder (bootmatrix.py --detach --serial-sock): use its serial.sock and qmp.sock")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    out = os.path.abspath(a.out)
    iso = os.path.abspath(a.iso)
    if a.attach:
        attach(a, out)
        return
    k, i = os.path.join(out, "vmlinuz"), os.path.join(out, "initrd.img")
    initrd = "/live/initrd.img" if a.kernel == "vmlinuz" else "/live/initrd2.img"
    extract(iso, "/live/" + a.kernel, k)
    extract(iso, initrd, i)
    qmp, ser = os.path.join(out, "qmp.sock"), os.path.join(out, "serial.sock")
    for p in (qmp, ser):
        if os.path.exists(p):
            os.unlink(p)
    cmd = ["qemu-system-x86_64", "-name", "beta-iso-lutz-session", "-machine", "q35,accel=kvm", "-cpu", "host", "-smp", "4",
           "-m", "6G", "-display", "none", "-vga", "std", "-nodefaults", "-monitor", "none",
           "-chardev", f"socket,id=s0,path={ser},server=on,wait=off", "-serial", "chardev:s0",
           "-qmp", f"unix:{qmp},server=on,wait=off", "-device", "qemu-xhci,id=xin", "-device", "usb-kbd,bus=xin.0",
           "-device", "usb-tablet,bus=xin.0", "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
           "-kernel", k, "-initrd", i, "-append", a.append + " console=tty0 console=ttyS0,115200",
           "-drive", f"file={iso},media=cdrom,if=none,id=cd0,readonly=on,format=raw", "-device", "ide-cd,drive=cd0"]
    if a.disk:
        cmd += ["-drive", f"file={os.path.abspath(a.disk)},if=virtio,format=raw"]
    if a.extra:
        cmd += a.extra.split()
    open(os.path.join(out, "cmdline.txt"), "w").write(" ".join(cmd) + "\n")
    p = subprocess.Popen(cmd, stdout=open(os.path.join(out, "qemu.log"), "w"), stderr=subprocess.STDOUT)
    t0 = time.time()
    s = Serial(ser, os.path.join(out, "serial.log"))
    q = Qmp(qmp)
    shots = [int(x) for x in a.shots.split(",") if x]
    report = open(os.path.join(out, "session.txt"), "w")
    ok = s.wait_for("login:", a.wait)
    report.write(f"# login prompt after {time.time() - t0:.0f} s: {ok}\n")
    if ok:
        s.send(a.user + "\n")
        s.wait_for("assword:", 20)
        s.send(a.password + "\n")
        s.read(4)
        s.send("PROMPT_COMMAND=; PS0=; bind 'set enable-bracketed-paste off'; export PS1='@@ ' TERM=dumb SYSTEMD_PAGER= PAGER=cat; stty cols 200\n")
        s.read(2)
        for line in (open(a.cmds).read().splitlines() if a.cmds else []):
            if not line.strip() or line.startswith("#"):
                continue
            if line.startswith("@shot "):
                q.cmd("screendump", filename=os.path.join(out, line.split()[1] + ".png"), format="png")
                report.write(f"@ screenshot {line.split()[1]}.png at {time.time() - t0:.0f} s\n\n")
                continue
            while shots and time.time() - t0 >= shots[0]:
                q.cmd("screendump", filename=os.path.join(out, f"t{shots.pop(0)}.png"), format="png")
            s.buf = b""
            s.send(line + "; echo __E''ND__\n")
            s.wait_for("__END__\r\n", 300)
            s.read(0.5)
            text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[a-zA-Z]", "", s.buf.decode(errors="replace")).replace("\r", "")
            text = (text.split("\n", 1)[1] if "\n" in text else text).split("__END__")[0]
            report.write(f"$ {line}\n{text.rstrip()}\n\n")
            report.flush()
    for t in shots:
        while time.time() - t0 < t:
            time.sleep(1)
        q.cmd("screendump", filename=os.path.join(out, f"t{t}.png"), format="png")
    report.write(f"# done after {time.time() - t0:.0f} s\n")
    if not a.keep:
        q.cmd("quit")
        p.wait(30)
    print(json.dumps({"login": ok, "seconds": round(time.time() - t0)}))


if __name__ == "__main__":
    main()
