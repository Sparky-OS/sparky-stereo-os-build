#!/usr/bin/env python3
"""Register a checksum-verified source descriptor against the starting inventory."""
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

notes = cfg.path('SPARKY_RUN_RECORD')
descriptor = Path(sys.argv[1]).resolve()
reason = sys.argv[2]
data = descriptor.read_text()
if data.startswith("-----BEGIN PGP SIGNED MESSAGE-----"):
    data = data.split("\n\n", 1)[1].split("\n-----BEGIN PGP SIGNATURE-----", 1)[0]
    data = "\n".join(line[2:] if line.startswith("- ") else line for line in data.splitlines())
fields = next(row for row in stanzas(data) if "checksums-sha256" in row)
name = fields["source"]

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

records = [f"{digest(descriptor)} {descriptor.stat().st_size} {descriptor.name}"]
for line in fields["checksums-sha256"].splitlines():
    if not line.strip():
        continue
    checksum, size, filename = line.split()
    assert Path(filename).name == filename
    path = descriptor.parent / filename
    assert path.stat().st_size == int(size) and digest(path) == checksum
    records.append(line.strip())
binaries = [
    row for row in json.loads((notes / "current-packages.json").read_text())
    if (row.get("Source", "").split(" ", 1)[0] or row["Package"]) == name
]
assert binaries, name
path = notes / "source-migration-overrides.json"
overrides = json.loads(path.read_text())
assert name not in overrides, "Review the existing source override instead of replacing it"
overrides[name] = {
    "source": name, "version": fields["version"], "directory": str(descriptor.parent),
    "files": "\n".join(records), "binaries": binaries, "reason": reason,
}
path.write_text(json.dumps(overrides, indent=2) + "\n")
print(name, fields["version"], "registered")
