#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/08
import pathlib
import subprocess
import sys
import tempfile

assert pathlib.Path("/.dockerenv").exists(), "Run in Docker only"
package = pathlib.Path(sys.argv[1]).resolve()
base = {
    "laptop": "1", "cpuinfo": "vendor_id : GenuineIntel\n", "lspci": "", "lsusb": "",
    "architecture": "amd64", "firmware-packages": "", "input-properties": "", "hid-uevents": "",
    "nvidia-detect": "",
}
cases = [
    ("ampere-laptop", {"laptop": "0", "lspci": "0000:01:00.0 0302: 10de:2504\n"}, {"nvidia-open", "nvidia-runtime-pm"}),
    ("turing-laptop", {"laptop": "0", "lspci": "0000:01:00.0 0300: 10de:1e04\n"}, {"nvidia-open", "nvidia-runtime-pm"}),
    ("nvidia-desktop", {"lspci": "0000:01:00.0 0300: 10de:2504\n"}, {"nvidia-open"}),
    ("older-laptop", {"laptop": "0", "lspci": "0000:01:00.0 0300: 10de:1b80\n"}, set()),
    ("unknown-laptop", {"laptop": "0", "lspci": "0000:01:00.0 0300: 10de:ffff\n"}, set()),
    ("mixed-laptop", {"laptop": "0", "lspci": "0000:01:00.0 0300: 10de:2504\n0000:02:00.0 0300: 10de:1b80\n"}, set()),
    ("audio-only", {"laptop": "0", "lspci": "0000:01:00.1 0403: 10de:228e\n"}, set()),
    ("nvidia-arm", {"laptop": "0", "architecture": "arm64", "lspci": "0000:01:00.0 0300: 10de:2504\n"}, set()),
    ("amd-laptop", {"laptop": "0", "cpuinfo": "vendor_id : AuthenticAMD\n", "lspci": "0000:04:00.0 0300: 1002:164e\n"}, {"amdgpu-dpm", "amdgpu-panel"}),
    ("amd-desktop", {"cpuinfo": "vendor_id : AuthenticAMD\n", "lspci": "0000:04:00.0 0300: 1002:164e\n"}, {"amdgpu-dpm"}),
    ("amd-cpu-only", {"cpuinfo": "vendor_id : AuthenticAMD\n"}, set()),
    ("radeon-on-intel", {"laptop": "0", "lspci": "0000:04:00.0 0300: 1002:164e\n"}, set()),
    ("no-gpu", {}, set()),
]
for name, changes, expected in cases:
    with tempfile.TemporaryDirectory() as directory:
        for fact, content in (base | changes).items():
            (pathlib.Path(directory) / fact).write_text(content)
        args = [sys.executable, str(package / "lib/detect.py"), directory, str(package / "share")]
        result = subprocess.check_output(args, text=True)
        actions = {line.split("\t")[1] for line in result.splitlines() if line.startswith("action\t")}
        assert actions == expected, (name, actions, expected)
        assert subprocess.check_output(args, text=True) == result, name
        print(f"PASS {name}: {', '.join(sorted(actions)) or 'no GPU action'}")
print(f"PASS {len(cases)} hardware power cases and repeatability")
