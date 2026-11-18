#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Refuse a simulation that does not uplift installed selected packages."""
import argparse
from pathlib import Path
import re


def verify(before, simulation, targets):
    installed = {}
    for line in before.splitlines():
        words = line.split()
        if len(words) == 3 and words[0] == 'ii':
            installed[words[1]] = words[2]
    offered = {}
    for line in simulation.splitlines():
        match = re.match(r'^Inst (\S+)(?: \[[^]]+\])? \((\S+)', line)
        if match:
            offered[match[1]] = match[2]
    failures, checked = [], 0
    for line in targets.splitlines():
        name, version = line.split()
        if name not in installed or installed[name] == version:
            continue
        checked += 1
        package, arch = name.rsplit(':', 1)
        found = offered.get(name, offered.get(package))
        if found != version:
            failures.append(f'{name}: installed {installed[name]}, expected Inst {version}, offered {found or "nothing"}')
    if not checked:
        failures.append('no installed selected package was tested for uplift')
    return checked, failures


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('before', type=Path)
    ap.add_argument('simulation', type=Path)
    ap.add_argument('targets', type=Path)
    args = ap.parse_args()
    checked, failures = verify(args.before.read_text(), args.simulation.read_text(), args.targets.read_text())
    print(f'Installed selected uplift targets: {checked}; failures: {len(failures)}')
    print('\n'.join(failures))
    raise SystemExit(bool(failures))
