#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""stage.py BUILD_DIR STAGE_DIR CHANGES_FILE [BUILD_LOG]: a source closure, copied (never linked) into STAGE_DIR: the .dsc
the .changes names and every file the .dsc names, every file the .changes names (packages, buildinfo), the .changes itself,
the build record (*.sparky-build.json of the same source and version) and the build log; then SHA256SUMS over all of them.
Stops if a named file is missing or its size or SHA-256 differs from what the .dsc or .changes says."""
import hashlib, re, shutil, sys
from pathlib import Path

build, stage, changes = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
log = Path(sys.argv[4]) if len(sys.argv) > 4 else None


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def named(control):
    text = control.read_text()
    block = re.search(r'^Checksums-Sha256:\n((?: .*\n?)+)', text, re.M)
    out = []
    for line in block.group(1).splitlines():
        digest, size, name = line.split()
        out.append((name, int(size), digest))
    return out


stage.mkdir(parents=True, exist_ok=False)
files = {changes.name}
for name, size, digest in named(changes):
    p = build / name
    if not p.is_file() or p.stat().st_size != size or sha(p) != digest:
        sys.exit(f"{name}: missing or not what {changes.name} says")
    files.add(name)
    if name.endswith('.dsc'):
        for n2, s2, d2 in named(p):
            q = build / n2
            if not q.is_file() or q.stat().st_size != s2 or sha(q) != d2:
                sys.exit(f"{n2}: missing or not what {name} says")
            files.add(n2)
source, version = re.search(r'^Source: (\S+)', changes.read_text(), re.M).group(1), \
    re.search(r'^Version: (\S+)', changes.read_text(), re.M).group(1)
records = sorted(build.glob(f"{source}_{version}_*.sparky-build.json"))
if not records:
    sys.exit(f"no build record {source}_{version}_*.sparky-build.json in {build}")
files.update(r.name for r in records)
for name in sorted(files):
    shutil.copy2(build / name, stage / name)
if log:
    shutil.copy2(log, stage / 'build.log')
    files.add('build.log')
lines = [f"{sha(stage / n)}  {n}" for n in sorted(files)]
(stage / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
print(f"{stage}: {len(files)} files, SHA256SUMS written")
