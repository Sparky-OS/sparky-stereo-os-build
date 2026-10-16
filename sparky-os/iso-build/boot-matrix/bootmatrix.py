#!/usr/bin/env python3
"""Boot one ISO in QEMU, headless, under one firmware setup, as a CD or as a USB disk.

Nothing is drawn on any display: QEMU runs with -display none and the screen is read back
through the QMP monitor (screendump to PNG). Keys are sent through QMP (send-key).

  bootmatrix.py --iso FILE --fw CASE --media cd|usb --out DIR [--ram 4G] [--cpus 4]
                [--steps "15:shot:menu,0:key:ret,45:shot:t60,60:shot:t120,..."]   (step kinds: shot, key, type, hmp)

CASE is one of:
  seabios        legacy BIOS (QEMU's SeaBIOS)
  ovmf           OVMF x64, Secure Boot off
  sb             OVMF x64, Secure Boot on, Microsoft keys of the distribution default (2011 and 2023 CAs)
  sb-sbat2024    as sb, plus the SbatLevel variable Windows' August 2024 update carries (shim,4 grub,3 grub.debian,4)
  sb-sbatlax     as sb, plus SbatLevel sbat,1,2099010100 (dated ahead, no revocations: shim keeps it) - A/B control for SBAT
  sb-2011only    Secure Boot on, db with only "Microsoft Corporation UEFI CA 2011"
  sb-2023only    Secure Boot on, db with only "Microsoft UEFI CA 2023"
  ia32           OVMF ia32 (32-bit UEFI) on a 64-bit CPU: mixed mode, Secure Boot off

The variable stores are made by fw/mkvars.sh (python3-virt-firmware) from the unpacked firmware packages.

Firmware files come from packages unpacked (dpkg -x, nothing installed) under FW_DIR:
  ovmf-forky/usr/share/OVMF/*      Debian forky ovmf-generic 2026.08+ds-2
  ovmf32-trixie/usr/share/OVMF/*   Debian trixie ovmf-ia32 2025.02-8+deb13u1 (forky dropped it)

The script writes DIR/result.json and DIR/*.png and exits 0 when QEMU ran the whole timeline.
"""
import argparse, json, os, shutil, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
FW_DIR = os.environ.get("FW_DIR", os.path.join(HERE, "fw"))


class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(100):
            try:
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("QMP socket never came up: " + path)
        self.f = self.s.makefile("rw")
        json.loads(self.f.readline())  # greeting
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                return {"error": "eof"}
            msg = json.loads(line)
            if "return" in msg or "error" in msg:
                return msg

    def shot(self, path):
        return self.cmd("screendump", filename=path, format="png")

    def key(self, *names):
        keys = [{"type": "qcode", "data": n} for n in names]
        return self.cmd("send-key", keys=keys)


SB_VARS = {"sb": "x64-ms-default", "sb-sbat2024": "x64-ms-default-sbat2024", "sb-sbatlax": "x64-ms-default-sbatlax",
           "sb-2011only": "x64-ms-2011only", "sb-2023only": "x64-ms-2023only"}


def firmware(case, out):
    """Return (machine args, firmware args, qemu binary); the variables are a private copy in OUT."""
    o64 = os.path.join(FW_DIR, "ovmf-forky/usr/share/OVMF")
    o32 = os.path.join(FW_DIR, "ovmf32-trixie/usr/share/OVMF")
    vars_path = os.path.join(out, "VARS.fd")
    flash = lambda code: ["-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
                          "-drive", f"if=pflash,format=raw,unit=1,file={vars_path}"]
    smm = ["-machine", "q35,accel=kvm,smm=on", "-global", "driver=cfi.pflash01,property=secure,value=on"]
    if case == "seabios":
        return ["-machine", "q35,accel=kvm"], [], "qemu-system-x86_64"
    if case == "ovmf":
        shutil.copy(os.path.join(FW_DIR, "vars/x64-empty.vars"), vars_path)
        return ["-machine", "q35,accel=kvm"], flash(os.path.join(o64, "OVMF_CODE_4M.fd")), "qemu-system-x86_64"
    if case in SB_VARS:
        shutil.copy(os.path.join(FW_DIR, "vars", SB_VARS[case] + ".vars"), vars_path)
        return smm, flash(os.path.join(o64, "OVMF_CODE_4M.secboot.fd")), "qemu-system-x86_64"
    if case == "ia32":
        shutil.copy(os.path.join(FW_DIR, "vars/ia32-empty.vars"), vars_path)
        return ["-machine", "q35,accel=kvm"], flash(os.path.join(o32, "OVMF32_CODE_4M.fd")), "qemu-system-x86_64"
    raise SystemExit("unknown case " + case)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso", required=True)
    ap.add_argument("--fw", required=True)
    ap.add_argument("--media", required=True, choices=["cd", "usb"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--ram", default="4G")
    ap.add_argument("--cpus", default="4")
    ap.add_argument("--vga", default="std")
    ap.add_argument("--steps", default="12:shot:menu,0:key:ret,40:shot:t50,40:shot:t90,45:shot:t135,45:shot:t180")
    ap.add_argument("--keep-vars", action="store_true")
    ap.add_argument("--vars", help="start from this UEFI variable store (a VARS.fd kept from an earlier run) instead of the template")
    ap.add_argument("--reboot", action="store_true", help="let the guest reboot (default: QEMU exits at a reboot)")
    ap.add_argument("--detach", action="store_true", help="start QEMU and return at once, its QMP socket free for vmctl.py")
    ap.add_argument("--disk", help="a second drive (raw), as virtio disk: an install target")
    ap.add_argument("--fat", help="a small FAT image as a further virtio disk (MokManager lists it)")
    ap.add_argument("--serial-sock", action="store_true", help="serial port on DIR/serial.sock instead of a log file (with --detach)")
    ap.add_argument("--offline", action="store_true", help="no network outside the VM (user networking with restrict=on)")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    machine, fwargs, binary = firmware(a.fw, a.out)
    if a.vars:
        shutil.copy(a.vars, os.path.join(a.out, "VARS.fd"))

    qmp_path = os.path.join(a.out, "qmp.sock")
    if os.path.exists(qmp_path):
        os.unlink(qmp_path)
    serial = os.path.join(a.out, "serial.log")
    iso = os.path.abspath(a.iso)
    if a.media == "cd":
        media = ["-drive", f"file={iso},media=cdrom,if=none,id=m0,readonly=on,format=raw",
                 "-device", "ide-cd,drive=m0,bootindex=0"]
    else:
        media = ["-drive", f"file={iso},if=none,id=m0,readonly=on,format=raw",
                 "-device", "qemu-xhci,id=xhci", "-device", "usb-storage,bus=xhci.0,drive=m0,bootindex=0"]
    cmd = [binary, "-name", f"beta-iso-lutz-{a.fw}-{a.media}", *machine, "-cpu", "host", "-smp", a.cpus, "-m", a.ram,
           "-display", "none", "-vga", a.vga,
           "-serial", (f"unix:{os.path.join(a.out, 'serial.sock')},server=on,wait=off" if a.serial_sock else f"file:{serial}"), "-monitor", "none",
           "-qmp", f"unix:{qmp_path},server=on,wait=off", *([] if a.reboot else ["-no-reboot"]), "-nodefaults",
           "-device", "qemu-xhci,id=xin", "-device", "usb-kbd,bus=xin.0",
           "-netdev", "user,id=n0" + (",restrict=on" if a.offline else ""), "-device", "virtio-net-pci,netdev=n0",
           *fwargs, *media]
    if a.disk:
        cmd += ["-drive", f"file={os.path.abspath(a.disk)},if=none,id=d0,format=raw", "-device", "virtio-blk-pci,drive=d0,bootindex=1"]
    if a.fat:
        cmd += ["-drive", f"file={os.path.abspath(a.fat)},if=none,id=f0,format=raw", "-device", "virtio-blk-pci,drive=f0,bootindex=5"]
    if a.detach:
        cmd += ["-device", "usb-tablet,bus=xin.0"]
    with open(os.path.join(a.out, "cmdline.txt"), "w") as f:
        f.write(" ".join(cmd) + "\n")
    t0 = time.time()
    qlog = open(os.path.join(a.out, "qemu.log"), "w")
    if a.detach:
        p = subprocess.Popen(cmd, stdout=qlog, stderr=subprocess.STDOUT, start_new_session=True)
        print(json.dumps({"fw": a.fw, "media": a.media, "qemu_pid": p.pid, "qmp": qmp_path}))
        return
    p = subprocess.Popen(cmd, stdout=qlog, stderr=subprocess.STDOUT)
    res = {"fw": a.fw, "media": a.media, "iso": iso, "steps": [], "qemu_pid": p.pid}
    try:
        q = Qmp(qmp_path)
        for st in a.steps.split(","):
            delay, kind, arg = st.split(":", 2)
            time.sleep(float(delay))
            if p.poll() is not None:
                res["steps"].append({"t": round(time.time() - t0, 1), "qemu_exited": p.returncode})
                break
            if kind == "shot":
                path = os.path.join(a.out, arg + ".png")
                r = q.shot(path)
                res["steps"].append({"t": round(time.time() - t0, 1), "shot": arg, "ok": "return" in r, "r": r})
            elif kind == "key":
                r = q.key(*arg.split("+"))
                res["steps"].append({"t": round(time.time() - t0, 1), "key": arg, "ok": "return" in r})
            elif kind == "hmp":
                # a monitor command (spaces written as underscores), output saved to hmp-<n>.txt: guest CPU state of a hung run
                r = q.cmd("human-monitor-command", **{"command-line": arg.replace("_", " ")})
                n = sum(1 for x in res["steps"] if "hmp" in x)
                with open(os.path.join(a.out, "hmp-%d.txt" % n), "w") as f:
                    f.write("# %s\n%s\n" % (arg.replace("_", " "), r.get("return", r)))
                res["steps"].append({"t": round(time.time() - t0, 1), "hmp": arg})
            elif kind == "type":
                # type a string with the keyboard (ascii letters, digits, space, - = / . only)
                names = []
                for ch in arg:
                    names.append({" ": "spc", "-": "minus", "=": "equal", "/": "slash", ".": "dot", ",": "comma"}.get(ch, ch))
                for n in names:
                    q.key(n)
                    time.sleep(0.05)
                res["steps"].append({"t": round(time.time() - t0, 1), "typed": arg})
    finally:
        alive = p.poll() is None
        res["qemu_alive_at_end"] = alive
        if alive:
            p.terminate()
            try:
                p.wait(10)
            except subprocess.TimeoutExpired:
                p.kill()
        res["seconds"] = round(time.time() - t0, 1)
        with open(os.path.join(a.out, "result.json"), "w") as f:
            json.dump(res, f, indent=1)
        if not a.keep_vars and os.path.exists(os.path.join(a.out, "VARS.fd")):
            pass
    print(json.dumps({k: res[k] for k in ("fw", "media", "seconds", "qemu_alive_at_end")}))


if __name__ == "__main__":
    main()
