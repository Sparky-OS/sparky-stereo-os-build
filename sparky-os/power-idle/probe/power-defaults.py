#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check packaged settings with native readers without applying host tunables."""

import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

EXPECTED = {
    "vm.max_map_count": 2147483642,
    "vm.swappiness": 100,
    "vm.vfs_cache_pressure": 50,
    "vm.dirty_bytes": 268435456,
    "vm.dirty_background_bytes": 67108864,
    "vm.dirty_writeback_centisecs": 1500,
    "vm.page-cluster": 0,
    "vm.watermark_boost_factor": 0,
    "vm.compaction_proactiveness": 0,
    "kernel.split_lock_mitigate": 0,
    "kernel.nmi_watchdog": 0,
    "net.core.netdev_max_backlog": 4096,
    "fs.file-max": 2097152,
    "kernel.unprivileged_userns_clone": 1,
    "kernel.kexec_load_disabled": 1,
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("payload", type=Path)
parser.add_argument("native_root", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--negative", choices=("size", "sysctl"))
args = parser.parse_args()
assert Path("/.dockerenv").exists(), "Run inside Docker"
args.payload = args.payload.resolve()
args.native_root = args.native_root.resolve()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
passed = []
details = {}


def run(command, env=None):
    result = subprocess.run([str(part) for part in command], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, (command, result.stdout, result.stderr)
    return result


def values(text):
    pairs = re.findall(r"^([\w.-]+)\s*=\s*(\d+)\s*$", text, re.M)
    assert len(pairs) == len(set(key for key, value in pairs)), "Duplicate sysctl key"
    return {key: int(value) for key, value in pairs}


try:
    config = args.payload / "usr/lib/sysctl.d/70-sparky-stereo.conf"
    if args.negative == "sysctl":
        changed = args.output / "wrong-sysctl.conf"
        changed.write_text(config.read_text().replace("vm.max_map_count = 2147483642", "vm.max_map_count = 65530"))
        config = changed
    assert values(config.read_text()) == EXPECTED, "Sysctl policy differs from the accepted reference"
    passed.append("all 15 packaged sysctl values match the reference")
    before = {key: Path("/proc/sys/" + key.replace(".", "/")).read_text()
              for key in EXPECTED if Path("/proc/sys/" + key.replace(".", "/")).exists()}
    dry_run = subprocess.run(["sysctl", "--dry-run", "-p", str(config)], text=True, capture_output=True)
    (args.output / "sysctl-dry-run.log").write_text(dry_run.stdout + dry_run.stderr)
    available = {key: EXPECTED[key] for key in before}
    assert values(dry_run.stdout) == available, dry_run.stdout
    missing = sorted(set(EXPECTED) - set(before))
    for key in missing:
        assert "cannot stat /proc/sys/" + key.replace(".", "/") in dry_run.stderr, dry_run.stderr
    assert dry_run.returncode == (1 if missing else 0), dry_run.returncode
    after = {key: Path("/proc/sys/" + key.replace(".", "/")).read_text() for key in before}
    assert before == after, "Dry-run changed a kernel value"
    details["native_sysctl_keys"] = sorted(available)
    details["unavailable_kernel_keys"] = missing
    passed.append(f"native procps dry-run parses {len(available)} available keys; kernel values unchanged")
    sysctl = args.native_root / "usr/lib/systemd/systemd-sysctl"
    native = run([sysctl, "--prefix=/__sparky_test_no_write__", config])
    (args.output / "systemd-sysctl.log").write_text(native.stdout + native.stderr)
    passed.append("native systemd-sysctl reads the file with an unmatched application prefix")

    generator = args.native_root / "usr/lib/systemd/system-generators/zram-generator"
    configuration = args.payload / "usr/lib/systemd/zram-generator.conf.d/sparky-stereo.conf"
    assert "compression-algorithm = zstd" in configuration.read_text()
    assert "fs-type = swap" in configuration.read_text()
    modprobe = args.output / "bin/modprobe"
    modprobe.parent.mkdir(exist_ok=True)
    modprobe.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"$MODPROBE_LOG\"\n")
    modprobe.chmod(0o755)
    rows = []
    for ram in (256, 1024, 4096, 8192, 16384, 65536):
        root = args.output / f"ram-{ram}/root"
        target = root.parent / "generated"
        root.mkdir(parents=True)
        (root / "proc").mkdir()
        (root / "proc/meminfo").write_text(f"MemTotal: {ram * 1024} kB\n")
        (root / "proc/cmdline").write_text("\n")
        conf = root / "usr/lib/systemd/zram-generator.conf.d/sparky-stereo.conf"
        conf.parent.mkdir(parents=True)
        content = configuration.read_text()
        if args.negative == "size":
            content = content.replace("min(ram, 8192)", "ram")
        conf.write_text(content)
        env = os.environ.copy()
        env["ZRAM_GENERATOR_ROOT"] = str(root)
        env["PATH"] = str(modprobe.parent) + ":" + env["PATH"]
        env["MODPROBE_LOG"] = str(args.output / "modprobe.log")
        generated = run([generator, target], env)
        (root.parent / "generator.log").write_text(generated.stdout + generated.stdout + generated.stderr)
        observed = re.search(r"/dev/zram0 with (\d+)MB", generated.stdout + generated.stderr)
        assert observed and int(observed[1]) == min(ram, 8192), f"Wrong native zram size for {ram} MiB"
        unit = (target / "dev-zram0.swap").read_text()
        assert "What=/dev/zram0\nPriority=100\n" in unit, unit
        assert sorted(path.name for path in target.glob("*.swap")) == ["dev-zram0.swap"]
        assert (target / "swap.target.wants/dev-zram0.swap").is_symlink()
        rows.append({"ram_mib": ram, "zram_mib": int(observed[1]), "priority": 100})
    details["zram"] = rows
    passed.append("native zram sizing and priority at six RAM sizes")

    root = args.output / "override/root"
    shutil.copytree(args.output / "ram-65536/root", root)
    override = root / "etc/systemd/zram-generator.conf.d/zz-user.conf"
    override.parent.mkdir(parents=True)
    override.write_text("[zram0]\nzram-size = 512\nswap-priority = 200\n")
    env["ZRAM_GENERATOR_ROOT"] = str(root)
    target = root.parent / "generated"
    generated = run([generator, target], env)
    assert "/dev/zram0 with 512MB" in generated.stdout + generated.stderr
    assert "Priority=200" in (target / "dev-zram0.swap").read_text()
    (root.parent / "generator.log").write_text(generated.stdout + generated.stdout + generated.stderr)
    passed.append("administrator zram override takes precedence")
    (root / "proc/cmdline").write_text("systemd.zram=0\n")
    disabled = root.parent / "disabled"
    run([generator, disabled], env)
    assert not list(disabled.glob("*.swap")), "Kernel opt-out created swap"
    passed.append("systemd.zram=0 creates no swap unit")
    assert set((args.output / "modprobe.log").read_text().splitlines()) == {"crypto-zstd"}
    passed.append("all module requests intercepted; no zram setup or swap activation")
except Exception as error:
    (args.output / "results.json").write_text(json.dumps({"passed": passed, "details": details,
                                                        "failure": str(error)}, indent=2) + "\n")
    raise
else:
    (args.output / "results.json").write_text(json.dumps({"passed": passed, "details": details,
                                                        "failure": None}, indent=2) + "\n")
