#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only check of the Cushion Swap File's log on a real system.

guest-log.py OUT.json [--seconds N]
    The log file and its folder belong to root:adm with 0640 and 0750; the
    file grows by one cycle at a time while the daemon runs; logrotate with
    the shipped /etc/logrotate.d/sparky-stereo-cushion-swap, forced twice as
    the daily timer would run it, rotates it (the second time compressing the
    first copy), and the daemon goes on writing to the same path; the journal
    holds the start and the thresholds but none of the per-cycle lines.
Exit 0 when everything matches, 1 on a mismatch, 2 when the probe cannot run.
Run as root in a disposable VM with sparky-stereo-cushion-swap installed.
"""

import argparse
import gzip
import json
import os
import re
import stat
import subprocess
import sys
import time
from pathlib import Path

LOG = Path("/var/log/cushion-swap/cushion-swap.log")
CONF = Path("/etc/logrotate.d/sparky-stereo-cushion-swap")


class Mismatch(Exception):
    pass


def command(*arguments, check=True):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)}: {result.stderr.strip()}")
    return result.stdout.strip()


def owner(path):
    info = path.stat()
    return {"mode": oct(stat.S_IMODE(info.st_mode)), "owner": command("stat", "-c", "%U:%G", str(path))}


def cycles(text):
    return [int(number) for number in re.findall(r"sample: .* cycle=(\d+)", text)]


def run(args, result):
    if command("systemctl", "is-active", "cushion-swap.service", check=False) != "active":
        raise Mismatch("cushion-swap.service is not running")
    unit = command("systemctl", "cat", "cushion-swap.service")
    result["unit"] = [line for line in unit.splitlines() if line.startswith(("StandardOutput", "StandardError", "LogNamespace", "Protect", "Private"))]
    result["folder"] = owner(LOG.parent)
    result["file"] = owner(LOG)
    if result["folder"] != {"mode": "0o750", "owner": "root:adm"} or result["file"] != {"mode": "0o640", "owner": "root:adm"}:
        raise Mismatch(f"Ownership: folder {result['folder']}, file {result['file']}")
    size0, cycles0 = LOG.stat().st_size, cycles(LOG.read_text(errors="replace"))
    time.sleep(args.seconds)
    size1, cycles1 = LOG.stat().st_size, cycles(LOG.read_text(errors="replace"))
    result["growing"] = {"bytes": [size0, size1], "last_cycle": [cycles0[-1] if cycles0 else None, cycles1[-1] if cycles1 else None],
                         "seconds": args.seconds}
    if not (size1 > size0 and cycles1 and cycles0 and cycles1[-1] > cycles0[-1]):
        raise Mismatch(f"The log file does not grow: {result['growing']}")
    rotations = []
    for run_number in (1, 2):
        before = cycles(LOG.read_text(errors="replace"))
        command("logrotate", "-f", str(CONF))
        time.sleep(args.seconds)
        after = cycles(LOG.read_text(errors="replace"))
        files = sorted(path.name for path in LOG.parent.iterdir())
        rotations.append({"run": run_number, "files": files, "last_cycle_before": before[-1] if before else None,
                          "first_cycle_after": after[0] if after else None, "last_cycle_after": after[-1] if after else None})
        if not after or not before or after[0] <= before[-1]:
            raise Mismatch(f"The daemon did not go on writing after rotation {run_number}: {rotations[-1]}")
    result["rotations"] = rotations
    one = LOG.with_name(LOG.name + ".1")
    two = LOG.with_name(LOG.name + ".2.gz")
    if not one.exists() or not two.exists():
        raise Mismatch(f"Rotated files missing: {rotations[-1]['files']}")
    rotated = cycles(gzip.decompress(two.read_bytes()).decode(errors="replace")) + cycles(one.read_text(errors="replace"))
    current = cycles(LOG.read_text(errors="replace"))
    every = rotated + current
    gaps = [(a, b) for a, b in zip(every, every[1:]) if b != a + 1]
    result["continuity"] = {"cycles": len(every), "gaps": gaps, "rotated_files": [owner(one), owner(two)]}
    if any(b <= a for a, b in gaps):
        raise Mismatch(f"Cycles out of order across the rotations: {gaps}")
    journal = command("journalctl", "-b", "-u", "cushion-swap.service", "-q", "--no-pager", "-o", "cat", check=False).splitlines()
    result["journal"] = {"lines": len(journal), "per_cycle": sum(1 for line in journal if re.search(r"sample:|deploy-check:|retract-check:", line)),
                         "start": [line for line in journal if "starting" in line or "thresholds (" in line][-2:],
                         "actions": [line for line in journal if re.search(r"DEPLOY|RETRACT|ERROR", line)][-6:]}
    if result["journal"]["per_cycle"] or not result["journal"]["start"]:
        raise Mismatch(f"The journal holds per-cycle lines or lacks the start: {result['journal']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=15)
    args = parser.parse_args()
    result = {"failure": None, "verified": False}
    status = 0
    try:
        if os.geteuid() != 0 or Path("/.dockerenv").exists():
            raise RuntimeError("Run as root in the disposable guest")
        command("systemd-detect-virt", "--vm")
        run(args, result)
        result["verified"] = True
    except Mismatch as error:
        result["failure"] = str(error)
        status = 1
    except Exception as error:
        result["failure"] = str(error)
        status = 2
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    os.sync()
    return status


if __name__ == "__main__":
    sys.exit(main())
