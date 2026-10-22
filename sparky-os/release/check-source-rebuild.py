#!/usr/bin/env python3
"""Rebuild retained script/tool sources and compare installed archive surfaces."""
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

base = cfg.path('SPARKY_MIGRATION_WORK')
kit = (cfg.TREE / 'sparky-os')


def surface(archive, control=False):
    data = subprocess.check_output([
        "dpkg-deb", "--ctrl-tarfile" if control else "--fsys-tarfile", str(archive)
    ])
    rows = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as stream:
        for item in stream:
            content = stream.extractfile(item).read() if item.isfile() else b""
            rows[item.name] = [item.type.decode(), item.mode, item.uid, item.gid,
                               item.linkname, hashlib.sha256(content).hexdigest()]
    return rows


for argument in sys.argv[1:]:
    category, name = argument.split(":", 1)
    if category not in ("scripts", "skills", "tooling", "meta") or "/" in name:
        raise SystemExit("Expected scripts|skills|tooling|meta:source-name")
    origin = base / category
    descriptors = list(origin.rglob(f"{name}_*.dsc")) if category == "scripts" else list(origin.glob(f"{name}_*.dsc"))
    descriptors = [path for path in descriptors
                   if not any('-attempt' in part for part in path.relative_to(origin).parts)]
    if len(descriptors) != 1:
        raise SystemExit(f"{name}: expected one source descriptor")
    dsc = descriptors[0]
    origin = dsc.parent
    fields = next(stanzas(dsc.read_text()))
    work = base / "source-rebuilds" / name
    work.mkdir(parents=True, exist_ok=False)
    shutil.copy2(dsc, work / dsc.name)
    for row in fields["checksums-sha256"].splitlines():
        if not row.strip():
            continue
        sha, size, filename = row.split()
        path = origin / filename
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assert path.stat().st_size == int(size) and digest == sha
        shutil.copy2(path, work / filename)
    recipe = """#!/bin/bash
set -euo pipefail
cd /work
dpkg-source -x "$TASK_DSC" source
if [ "$TASK_SOURCE" = vibe ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    apt-get -y --no-install-recommends build-dep /work/source
fi
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd source
runuser -u builder -- dpkg-buildpackage -us -uc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*.deb
if [ "$TASK_SOURCE" = dpkg-stereo ] && [ "${TOOLKIT_HOOK_TEST:-}" = 1 ]; then
    sh /toolkit/packages/dpkg-stereo/test/upgrade-test.sh /work/dpkg-stereo_*_all.deb /work/hook-proof > /work/hook-proof.log 2>&1
fi
"""
    (work / "run.sh").write_text(recipe)
    with (work / "build.log").open("wb") as log:
        process = start_build([
            "docker", "run", "--rm", "--platform", "linux/amd64", "--name", "sparky-lc-source-" + name,
            "--cpus", "2", "-e", "TASK_DSC=" + dsc.name,
            "-e", "TASK_SOURCE=" + name,
            "-v", f"{work}:/work", "-v", f"{kit}:/toolkit:ro",
            "sparky-lc-migration:20261020", "bash", "/work/run.sh",
        ], 'sparky-lc-source-' + name, log)
        if process.wait():
            raise SystemExit(f'{name}: retained-source rebuild failed')
    expected = {p.name for p in origin.glob(name + "_*.deb")}
    expected |= {p.name for p in origin.glob(name + "-lc-hr_*.deb")}
    if category == "meta":
        expected = {p.name for p in origin.glob("*.deb")
                    if subprocess.check_output(
                        ["dpkg-deb", "-f", str(p), "Source"], text=True
                    ).split()[0] == name}
    actual = {p.name for p in work.glob("*.deb")}
    assert expected and actual == expected, (name, expected, actual)
    comparisons = []
    for filename in sorted(expected):
        for control in (False, True):
            first, second = surface(origin / filename, control), surface(work / filename, control)
            differences = sorted(key for key in first.keys() | second.keys()
                                 if first.get(key) != second.get(key))
            comparisons.append({"archive": filename, "control": control,
                                "differences": differences})
    report = {"source": name, "descriptor": dsc.name,
              "passed": all(not r["differences"] for r in comparisons),
              "comparisons": comparisons}
    (work / "comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    print(name, "PASS" if report["passed"] else "FAIL", flush=True)
    if not report["passed"]:
        raise SystemExit(1)
