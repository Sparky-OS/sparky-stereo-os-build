#!/usr/bin/python3 -I
"""mkguest.py KERNEL_ROOT OUT_DIR [--sdl-lib FILE] [--modules a,b,c] [--bins DIR]...: assembles the lab's small guest from
an unpacked kernel package: its vmlinuz, the named modules (decompressed, in the order depmod gives), a static BusyBox,
the static test programs and, when SDL is wanted, sdltest with the closure of its shared libraries and optionally the
SDL3 library under test. Writes OUT_DIR/vmlinuz and OUT_DIR/initrd.gz. Runs in the lab22-guest image."""
import argparse
import glob
import gzip
import os
import re
import shutil
import subprocess
import sys

ap = argparse.ArgumentParser()
ap.add_argument("kroot")
ap.add_argument("out")
ap.add_argument("--sdl-lib")
ap.add_argument("--modules", default="")
ap.add_argument("--bins", action="append", default=[])
ap.add_argument("--init", required=True)
ap.add_argument("--modarg", action="append", default=[], help="NAME=ARGS: parameters for insmod of module NAME")
ap.add_argument("--tree", action="append", default=[], help="a folder copied into the root as it is (phases, data, src)")
a = ap.parse_args()

mods_root = (glob.glob(a.kroot + "/lib/modules/*") + glob.glob(a.kroot + "/usr/lib/modules/*"))
mods_root = [m for m in mods_root if os.path.isdir(m + "/kernel")]
if not mods_root:
    print("no module folder in", a.kroot)
    sys.exit(2)
mdir = mods_root[0]
kver = os.path.basename(mdir)
vm = (glob.glob(a.kroot + "/boot/vmlinuz-*") + glob.glob(mdir + "/vmlinuz*"))
if not vm:
    print("no vmlinuz in", a.kroot)
    sys.exit(2)
work = os.path.join(a.out, "root")
shutil.rmtree(work, ignore_errors=True)
for d in ("bin", "dev", "proc", "sys", "tmp", "lib/lab-modules", "opt/sdl", "run"):
    os.makedirs(os.path.join(work, d), exist_ok=True)
shutil.copy(vm[0], os.path.join(a.out, "vmlinuz"))
bb = shutil.which("busybox")
shutil.copy(bb, work + "/bin/busybox")
for applet in ("sh", "mount", "insmod", "sleep", "cat", "ls", "poweroff", "mkdir", "echo", "dmesg", "grep", "head", "wc", "test", "env", "cp", "sed"):
    os.symlink("busybox", work + "/bin/" + applet)

# modules in dependency order, from a depmod run on a scratch copy of the module tree's index
tmp = os.path.join(a.out, "depmod")
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp + "/lib/modules")
os.symlink(os.path.join(mdir, "kernel"), tmp + "/lib/modules/" + kver + "") if False else None
subprocess.run(["cp", "-as", mdir, tmp + "/lib/modules/" + kver], check=True)
for f in ("modules.order", "modules.builtin", "modules.builtin.modinfo"):
    if os.path.exists(mdir + "/" + f):
        subprocess.run(["cp", "-f", mdir + "/" + f, tmp + "/lib/modules/" + kver + "/" + f])
r = subprocess.run(["depmod", "-b", tmp, kver], capture_output=True, text=True)
dep = {}
for line in open(tmp + "/lib/modules/" + kver + "/modules.dep"):
    k, _, v = line.partition(":")
    dep[k.strip()] = v.split()
builtin = set()
bf = mdir + "/modules.builtin"
if os.path.exists(bf):
    builtin = {os.path.basename(l.strip()).split(".")[0].replace("-", "_") for l in open(bf)}


def modpath(name):
    n = name.replace("_", "[-_]")
    for k in dep:
        base = re.sub(r"\.ko(\.xz|\.zst|\.gz)?$", "", os.path.basename(k))
        if base.replace("-", "_") == name.replace("-", "_"):
            return k
    return None


order = []


def add(k):
    for d in dep.get(k, []):
        add(d)
    if k not in order:
        order.append(k)


skipped = []
for m in [x for x in a.modules.split(",") if x]:
    k = modpath(m)
    if k is None:
        if m.replace("-", "_") in builtin:
            skipped.append(m + " (built in)")
        else:
            skipped.append(m + " (not in this kernel)")
        continue
    add(k)
lines = []
for i, k in enumerate(order):
    src = os.path.join(mdir, k) if not os.path.isabs(k) else k
    base = re.sub(r"\.(xz|zst|gz)$", "", os.path.basename(k))
    dst = "%s/lib/lab-modules/%02d-%s" % (work, i, base)
    if k.endswith(".xz"):
        data = subprocess.run(["xz", "-dc", src], capture_output=True, check=True).stdout
    elif k.endswith(".zst"):
        data = subprocess.run(["zstd", "-dc", src], capture_output=True, check=True).stdout
    elif k.endswith(".gz"):
        data = gzip.open(src).read()
    else:
        data = open(src, "rb").read()
    open(dst, "wb").write(data)
    nm = re.sub(r"\.ko$", "", base).replace("-", "_")
    extra = " ".join(x.split("=", 1)[1] for x in a.modarg if x.split("=", 1)[0].replace("-", "_") == nm)
    lines.append(("insmod /lib/lab-modules/%02d-%s %s" % (i, base, extra)).rstrip())
open(work + "/lib/lab-modules/load.sh", "w").write("\n".join(lines) + "\n")
print("modules:", [os.path.basename(k) for k in order], "skipped:", skipped)

for d in a.bins:
    for f in glob.glob(d + "/*"):
        shutil.copy(f, work + "/bin/" + os.path.basename(f))
        os.chmod(work + "/bin/" + os.path.basename(f), 0o755)
if os.path.exists(work + "/bin/sdltest"):
    out = subprocess.run(["ldd", work + "/bin/sdltest"], capture_output=True, text=True).stdout
    for m in re.finditer(r"=> (/\S+)|^\s*(/\S+) \(", out, re.M):
        p = m.group(1) or m.group(2)
        dst = work + p
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):
            shutil.copy(os.path.realpath(p), dst)
    if a.sdl_lib:
        shutil.copy(a.sdl_lib, work + "/opt/sdl/libSDL3.so.0")
for t in a.tree:
    subprocess.run(["cp", "-a", t + "/.", work + "/"], check=True)
shutil.copy(a.init, work + "/init")
os.chmod(work + "/init", 0o755)
find = subprocess.Popen(["find", ".", "-print0"], cwd=work, stdout=subprocess.PIPE)
cpio = subprocess.Popen(["cpio", "-0", "-o", "-H", "newc", "--quiet"], cwd=work, stdin=find.stdout, stdout=subprocess.PIPE)
with open(a.out + "/initrd.gz", "wb") as f:
    gz = subprocess.Popen(["gzip", "-1"], stdin=cpio.stdout, stdout=f)
    gz.wait()
shutil.rmtree(work)
shutil.rmtree(tmp)
print("initrd", os.path.getsize(a.out + "/initrd.gz"))
