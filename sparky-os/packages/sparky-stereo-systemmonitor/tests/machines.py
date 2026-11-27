#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixture computers for the Overview presets' tests: sysfs and procfs trees in the shape the kernel gives them (each
card a directory under its bridge, /sys/bus/pci/devices holding links to them), and an nvidia-smi stand-in replaying
recorded output. The station and the A10 rows are the two test targets as read on 2026-11-27 (read-only); the others are
synthetic computers with real IDs."""
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent

# card: address, bridge (None: on the root bus), vendor, device, class, driver, boot_vga, files {name: text},
# hwmon {name: [files]} (None: no hwmon)
MACHINES = {
    "station": {
        "threads": 12, "smi": "station.txt",
        "cards": [
            ("0000:01:00.0", "0000:00:01.1", "0x10de", "0x2504", "0x030000", "nvidia", "0", {}, None),
            ("0000:0b:00.0", "0000:00:08.1", "0x1002", "0x1638", "0x030000", "amdgpu", "1",
             {"gpu_busy_percent": "4", "mem_info_vram_total": "536870912", "mem_info_vram_used": "300000000"},
             {"amdgpu": ["temp1_input", "temp1_label", "power1_input", "power1_label", "in0_input", "freq1_input"]}),
        ],
    },
    "a10": {
        "threads": 4,
        "cards": [
            ("0000:00:01.0", None, "0x1002", "0x9874", "0x030000", "amdgpu", "1",
             {"gpu_busy_percent": "0", "mem_info_vram_total": "536870912", "mem_info_vram_used": "120000000"},
             {"amdgpu": ["temp1_input", "temp1_label", "power1_label", "in0_input", "freq1_input"]}),
            ("0000:03:00.0", "0000:00:03.1", "0x1002", "0x6660", "0x038000", "amdgpu", None,
             {"mem_info_vram_total": "2147483648", "mem_info_vram_used": "5000000"},
             {"amdgpu": ["temp1_input", "temp1_label", "power1_label", "freq1_input", "freq2_input"]}),
        ],
    },
    "one-amd": {
        "threads": 12,
        "cards": [
            ("0000:0b:00.0", "0000:00:08.1", "0x1002", "0x1638", "0x030000", "amdgpu", "1",
             {"gpu_busy_percent": "4", "mem_info_vram_total": "536870912", "mem_info_vram_used": "300000000"},
             {"amdgpu": ["temp1_input", "power1_input"]}),
        ],
    },
    "intel-i915": {
        "threads": 8, "paranoid": "3", "pmu": ["i915"],
        "cards": [("0000:00:02.0", None, "0x8086", "0xa780", "0x030000", "i915", "1", {}, None)],
    },
    "intel-i915-perf": {
        "threads": 8, "paranoid": "-1", "pmu": ["i915"],
        "cards": [("0000:00:02.0", None, "0x8086", "0xa780", "0x030000", "i915", "1", {}, None)],
    },
    "intel-xe": {
        "threads": 16, "paranoid": "-1",
        "cards": [("0000:00:02.0", None, "0x8086", "0x7d55", "0x030000", "xe", "1", {}, None)],
    },
    "laptop-intel-nvidia": {
        "threads": 16, "paranoid": "3", "pmu": ["i915"], "smi": "laptop-na.txt",
        "cards": [
            ("0000:00:02.0", None, "0x8086", "0x9a49", "0x030000", "i915", "1", {}, None),
            ("0000:01:00.0", "0000:00:01.0", "0x10de", "0x25a2", "0x030200", "nvidia", "0", {}, None),
        ],
    },
    "nouveau": {
        "threads": 4,
        "cards": [("0000:01:00.0", "0000:00:01.0", "0x10de", "0x1f08", "0x030000", "nouveau", "1", {}, None)],
    },
    "nvidia-no-smi": {
        "threads": 6, "smi": None,
        "cards": [("0000:01:00.0", "0000:00:01.0", "0x10de", "0x2504", "0x030000", "nvidia", "1", {}, None)],
    },
    "virtio": {
        "threads": 2,
        "cards": [("0000:00:01.0", None, "0x1af4", "0x1050", "0x030000", "virtio-pci", "1", {}, None)],
    },
    "server-bmc": {
        "threads": 32,
        "cards": [
            ("0000:03:00.0", "0000:00:1c.0", "0x1a03", "0x2000", "0x030000", "ast", "1", {}, None),
            ("0000:41:00.0", "0000:40:01.1", "0x1002", "0x744c", "0x030000", "amdgpu", "0",
             {"gpu_busy_percent": "0", "mem_info_vram_total": "25753026560", "mem_info_vram_used": "400000000"},
             {"amdgpu": ["temp1_input", "power1_average"]}),
        ],
    },
    "five-amd": {
        "threads": 64,
        "cards": [("0000:%02x:00.0" % b, "0000:00:%02x.0" % b, "0x1002", "0x73bf", "0x030000", "amdgpu",
                   "1" if b == 0x21 else "0",
                   {"gpu_busy_percent": "1", "mem_info_vram_total": "17163091968", "mem_info_vram_used": "1"},
                   {"amdgpu": ["temp1_input", "power1_average"]}) for b in (0x21, 0x22, 0x23, 0x24, 0x25)],
    },
    "no-pci": {"threads": 4, "cards": None},
}


def build(name, root):
    """Writes the machine NAME under ROOT (sys, proc, nvidia-smi) and returns the environment for overview-pages."""
    m = MACHINES[name]
    root = Path(root)
    sysfs, procfs = root / "sys", root / "proc"
    (procfs / "sys/kernel").mkdir(parents=True, exist_ok=True)
    (procfs / "cpuinfo").write_text("".join("processor\t: %d\nmodel name\t: fixture\n\n" % i
                                            for i in range(m["threads"])))
    (procfs / "sys/kernel/perf_event_paranoid").write_text(m.get("paranoid", "3") + "\n")
    for pmu in m.get("pmu", []):
        (sysfs / "bus/event_source/devices" / pmu).mkdir(parents=True, exist_ok=True)
    if m["cards"] is not None:
        links = sysfs / "bus/pci/devices"
        links.mkdir(parents=True, exist_ok=True)
        for address, bridge, vendor, device, cls, driver, boot_vga, files, hwmon in m["cards"]:
            path = sysfs / "devices/pci0000:00"
            if bridge:
                path = path / bridge
            path = path / address
            path.mkdir(parents=True)
            for key, value in (("vendor", vendor), ("device", device), ("class", cls)):
                (path / key).write_text(value + "\n")
            if boot_vga is not None:
                (path / "boot_vga").write_text(boot_vga + "\n")
            if driver:
                (sysfs / "bus/pci/drivers" / driver).mkdir(parents=True, exist_ok=True)
                os.symlink(os.path.relpath(sysfs / "bus/pci/drivers" / driver, path), path / "driver")
            for key, value in files.items():
                (path / key).write_text(value + "\n")
            for index, (chip, entries) in enumerate((hwmon or {}).items()):
                chip_dir = path / "hwmon" / ("hwmon%d" % (index + 2))
                chip_dir.mkdir(parents=True)
                (chip_dir / "name").write_text(chip + "\n")
                for entry in entries:
                    (chip_dir / entry).write_text("1\n")
            os.symlink(os.path.relpath(path, links), links / address)
    env = {"SPARKY_STEREO_SYSFS": str(sysfs), "SPARKY_STEREO_PROCFS": str(procfs)}
    smi = m.get("smi", "station.txt")
    stub = root / "nvidia-smi"
    if smi is None:
        env["SPARKY_STEREO_NVIDIA_SMI"] = str(root / "absent-nvidia-smi")
    else:
        query, dmon = (HERE / "fixtures/nvidia-smi" / smi).read_text().split("====\n")
        (root / "query.txt").write_text(query)
        (root / "dmon.txt").write_text(dmon)
        stub.write_text('#!/bin/sh\ncase "$1" in\n  dmon) cat "%s" ;;\n  --query-gpu=*) cat "%s" ;;\n'
                        '  *) echo "unexpected $*" >&2; exit 2 ;;\nesac\n' % (root / "dmon.txt", root / "query.txt"))
        stub.chmod(0o755)
        env["SPARKY_STEREO_NVIDIA_SMI"] = str(stub)
    return env
