#!/usr/bin/env python3
"""Build another architecture from the exact prepared amd64 source descriptor.

Defaults to i386; SECONDARY_ARCH=arm64 selects the edition's ARM client build.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

base = cfg.path('SPARKY_MIGRATION_WORK')
repo = cfg.path('SPARKY_REPO_DIR')
kit = (cfg.TREE / 'sparky-os')
architecture = os.environ.get('SECONDARY_ARCH', 'i386')
if architecture not in ('i386', 'arm64'):
    raise SystemExit('Supported secondary architectures: i386, arm64')
platform = 'linux/386' if architecture == 'i386' else 'linux/arm64'
recipe = r"""#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS=parallel=4
printf 'deb [trusted=yes] file:/repo ./\n' >/etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' >/etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' >/etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' >/etc/apt/preferences.d/edition
if [ "$TASK_ARCH" = arm64 ]; then
    # This is the standalone ARM receiver, not an ARM build of the desktop
    # stack. Edition Architecture:all KDE data cannot be mixed with Debian's
    # newer ARM libraries. Its retained source has no edition-only build deps.
    rm /etc/apt/sources.list.d/edition.list /etc/apt/preferences.d/edition
fi
cd /work
dpkg-source -x "$TASK_DSC" source
if [ -f /work/build-inputs.json ]; then
    printf 'deb [trusted=yes] file:/work/dependency-packages ./\n' > /etc/apt/sources.list.d/build-inputs.list
    python3 - <<'VERIFIED_INPUTS'
from pathlib import Path
import hashlib, json
items = json.loads(Path('/work/build-inputs.json').read_text())
for item in items:
    assert hashlib.sha256((Path('/work/dependency-packages') / item['archive']).read_bytes()).hexdigest() == item['sha256']
Path('/etc/apt/preferences.d/verified-build-inputs').write_text(''.join(
    f"Package: {item['package']}\nPin: version {item['version']}\nPin-Priority: 1002\n\n" for item in items))
VERIFIED_INPUTS
fi
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
if [ -f /work/build-inputs.json ]; then
    python3 - <<'CHECK_INPUTS'
from pathlib import Path
import json, subprocess
for item in json.loads(Path('/work/build-inputs.json').read_text()):
    actual = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', item['package']], text=True)
    assert actual == item['version'], (item['package'], actual, item['version'])
CHECK_INPUTS
fi
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- dpkg-buildpackage -us -uc -B -j4
cp .sparky-lc/source.json ../native-source.json
tar -cJf ../native-authored-evidence.tar.xz .sparky-lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_"$TASK_ARCH".deb
"""
for name in sys.argv[1:]:
    primary = base / "jobs" / (name + "-amd64")
    primary_status = json.loads((primary / "status.json").read_text())
    if primary_status["state"] != "candidate-needs-review":
        raise SystemExit(f"{name}: primary architecture has not passed its build")
    descriptors = list(primary.glob("*+lc1.dsc"))
    if len(descriptors) != 1:
        raise SystemExit(f"{name}: need one reviewed source descriptor")
    dsc = descriptors[0]
    fields = next(stanzas(dsc.read_text()))
    work = base / "jobs" / (name + "-" + architecture)
    if (work / "status.json").exists():
        print(f"{name}: existing checkpoint", flush=True)
        continue
    if shutil.disk_usage(base).free < 14 * 1024**3:
        raise SystemExit("Disk below start threshold")
    work.mkdir(parents=True, exist_ok=False)
    if (primary / 'build-inputs.json').exists():
        inputs = json.loads((primary / 'build-inputs.json').read_text())
        dependencies = work / 'dependency-packages'
        dependencies.mkdir()
        for item in inputs:
            archive = primary / 'dependency-packages' / item['archive']
            if subprocess.check_output(['dpkg-deb', '-f', str(archive), 'Architecture'], text=True).strip() != 'all':
                if name != 'wine' or architecture != 'i386':
                    raise SystemExit('Secondary build needs separately qualified architecture-specific dependency inputs')
                retained = base / 'wine-build-inputs'
                candidates = [r for r in json.loads((retained / 'verified-packages.json').read_text())
                              if r['package'] == item['package'] and r['version'] == item['version']
                              and r['architecture'] == architecture]
                assert len(candidates) == 1
                record = candidates[0]
                archive = retained / record['filename']
                assert archive.stat().st_size == record['size']
                item.update(archive=archive.name, architecture=architecture, sha256=record['sha256'],
                            source_job=str(retained))
            assert hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256']
            shutil.copy2(archive, dependencies / archive.name)
        with (dependencies / 'Packages').open('w') as index:
            subprocess.run(['dpkg-scanpackages', '.', '/dev/null'], cwd=dependencies, stdout=index, check=True)
        (work / 'build-inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    shutil.copy2(dsc, work / dsc.name)
    for row in fields["checksums-sha256"].splitlines():
        if not row.strip():
            continue
        expected, size, filename = row.split()
        original = primary / filename
        with original.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected or original.stat().st_size != int(size):
            raise SystemExit(f"Source integrity failure: {original}")
        shutil.copy2(original, work / filename)
    (work / "run.sh").write_text(recipe)
    container = "sparky-lc-" + name + "-" + architecture
    command = ["docker", "run", "--rm", "--platform", platform,
               "--name", container, "--cpus", "4", "-e", f"TASK_DSC={dsc.name}",
               "-e", f"TASK_ARCH={architecture}",
               "-v", f"{work}:/work", "-v", f"{repo}:/repo:ro",
               "-v", f"{kit}:/toolkit:ro",
               "-v", "/usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro",
               "sparky-lc-migration:20261020-" + architecture, "bash", "/work/run.sh"]
    print(f"{name}: {architecture} from {dsc.name}", flush=True)
    start = time.time()
    stopped = False
    with (work / "build.log").open("wb") as log:
        process = start_build(command, container, log)
        while process.poll() is None:
            if shutil.disk_usage(base).free < 12 * 1024**3:
                subprocess.run(["docker", "stop", "-t", "20", container], check=False)
                stopped = True
                break
            time.sleep(5)
        result = process.wait()
    record = {"source": name, "version": fields["version"], "architecture": architecture,
              "exit_code": result, "disk_floor_stop": stopped,
              "seconds": round(time.time() - start, 1),
              "source_descriptor_sha256": hashlib.sha256(dsc.read_bytes()).hexdigest(),
              "state": "candidate-needs-review" if result == 0 else "needs-repair",
              "archives": sorted(p.name for p in work.glob("*+lc1_" + architecture + ".deb"))}
    (work / "status.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"{name}: {record['state']}, exit {result}", flush=True)
    if stopped:
        raise SystemExit("Own build stopped at disk floor")
    if result:
        raise SystemExit(f"{name}: build failed; review its checkpoint")
