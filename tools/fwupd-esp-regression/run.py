#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Compile the supplied, unchanged FuVolumeLocker against a volume test double."""
import argparse
import hashlib
from pathlib import Path
import shlex
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path, help="fwupd source tree")
parser.add_argument("output", type=Path, help="disposable build directory")
parser.add_argument("--cc", default="gcc")
args = parser.parse_args()
here = Path(__file__).resolve().parent
args.output.mkdir(parents=True, exist_ok=True)
for name in ("fu-volume-locker.c", "fu-volume-locker.h"):
    src = args.source / "libfwupdplugin" / name
    shutil.copyfile(src, args.output / name)
    print(f"SHA256 {name} {hashlib.sha256(src.read_bytes()).hexdigest()}", flush=True)
shutil.copyfile(args.source / "libfwupd" / "fwupd-build.h", args.output / "fwupd-build.h")
shutil.copyfile(here / "volume-double.h", args.output / "fu-volume.h")
(args.output / "config.h").write_text("")
flags = shlex.split(subprocess.check_output(
    ["pkgconf", "--cflags", "--libs", "gio-2.0"], text=True))
exe = (args.output / "locker-test").resolve()
subprocess.run([args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror",
                "-Wno-unused-parameter", f"-I{args.output}",
                str(args.output / "fu-volume-locker.c"),
                str(here / "locker-test.c"), "-o", str(exe), *flags], check=True)
failed = 0
for case in ("external-mounted", "owned-finalize", "owned-explicit-close",
             "mount-failure", "external-stale-cache"):
    failed += subprocess.run([str(exe), case]).returncode != 0
print(f"{failed} failed / 5 cases", flush=True)
raise SystemExit(bool(failed))
