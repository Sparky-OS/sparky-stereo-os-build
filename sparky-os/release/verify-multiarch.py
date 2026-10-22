#!/usr/bin/env python3
"""Compare shared files of completed Multi-Arch:same candidate pairs."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

base = cfg.path('SPARKY_MIGRATION_WORK')
records = []
for name in sys.argv[1:]:
    primary = base / "jobs" / (name + "-amd64")
    secondary = base / "jobs" / (name + "-i386")
    first_status = json.loads((primary / "status.json").read_text())
    second_status = json.loads((secondary / "status.json").read_text())
    assert first_status["state"] == second_status["state"] == "candidate-needs-review"
    descriptors = list(primary.glob("*+lc1.dsc"))
    assert len(descriptors) == 1
    assert hashlib.sha256(descriptors[0].read_bytes()).hexdigest() == second_status["source_descriptor_sha256"]
    for first in primary.glob("*+lc1_amd64.deb"):
        fields = next(stanzas(subprocess.check_output(["dpkg-deb", "-f", str(first)], text=True)))
        if fields.get("multi-arch") != "same":
            continue
        second = secondary / first.name.replace("_amd64.deb", "_i386.deb")
        if not second.exists():
            raise SystemExit(f"Missing twin: {second}")

        def payload(archive):
            raw = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(archive)])
            with tarfile.open(fileobj=io.BytesIO(raw)) as stream:
                return {item.name: (item.type.decode(), item.mode, item.linkname,
                                    hashlib.sha256(stream.extractfile(item).read()).hexdigest()
                                    if item.isfile() else None)
                        for item in stream if not item.isdir()}

        a, b = payload(first), payload(second)
        common = a.keys() & b.keys()
        changed = sorted(path for path in common if a[path] != b[path])
        records.append({"package": fields["package"], "version": fields["version"],
                        "shared_files": len(common), "different": changed})
        print(fields["package"], "PASS" if not changed else "FAIL",
              f"{len(common)} shared paths", changed)
output = base / "logs" / ("multiarch-" + "-".join(sys.argv[1:]) + ".json")
output.write_text(json.dumps(records, indent=2) + "\n")
if any(record["different"] for record in records):
    raise SystemExit(1)
