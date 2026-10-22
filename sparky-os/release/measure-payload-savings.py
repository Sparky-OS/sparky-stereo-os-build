#!/usr/bin/env python3
"""Measure payload projection separately from source projection and cache removal."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import lzma
from pathlib import Path
import subprocess
import sys
import tarfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import load, manifest_path

progress = json.loads((notes / "migration-progress.json").read_text())
selected = {}
for row in progress["archives"]:
    package, arch = row["Package"], row["Architecture"]
    if arch not in ("amd64", "all") or package.endswith(("-lc-hr", "-dbgsym")):
        continue
    key = package, arch
    if key in selected:
        previous = selected[key]
        newer = subprocess.run(
            ["dpkg", "--compare-versions", row["Version"], "gt", previous["Version"]]
        ).returncode == 0
        if not newer:
            continue
    selected[key] = row


def measure(row):
    wanted = manifest_path(row["Package"], row["Architecture"])
    proc = subprocess.Popen(
        ["dpkg-deb", "--fsys-tarfile", row["archive"]],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    raw = None
    try:
        with tarfile.open(fileobj=proc.stdout, mode="r|") as archive:
            for member in archive:
                if "/" + member.name.removeprefix("./").lstrip("/") == wanted:
                    raw = archive.extractfile(member).read()
                    break
    finally:
        proc.stdout.close()
        if proc.poll() is None:
            proc.terminate()
        proc.wait()
    if raw is None:
        raise RuntimeError(f"Missing manifest in {row['archive']}")
    manifest = load(row["Sparky-Lean-Code"], raw, row["Package"],
                    row["Version"], row["Architecture"])
    projected = [item for item in manifest["files"] if item["status"] == "projected"]
    before = sum(item["bytes_hr"] for item in projected)
    after = sum(item["bytes"] for item in projected)
    return {
        "package": row["Package"], "version": row["Version"],
        "architecture": row["Architecture"],
        "files": len(projected), "before": before, "after": after,
        "gross_saved": before - after, "manifest_bytes": len(raw),
        "net_text_minus_manifest": before - after - len(raw),
        "experimental_xz_manifest_bytes": len(lzma.compress(raw, preset=6)),
    }


with ThreadPoolExecutor(max_workers=2) as pool:
    rows = list(pool.map(measure, selected.values()))
keys = ("files", "before", "after", "gross_saved", "manifest_bytes",
        "net_text_minus_manifest", "experimental_xz_manifest_bytes")
report = {
    "time": datetime.now(timezone.utc).isoformat(),
    "candidate_checkpoint": progress["time"],
    "scope": "One current staged amd64/all candidate per package; excludes HR and dbgsym packages. "
             "Sum of uncompressed payload text reductions, minus manifest file sizes only. "
             "Not a measured installed system, download, ISO, filesystem-block or performance delta. "
             "Package-shared paths are not deduplicated; source reductions are not added. "
             "Experimental XZ sizes are a storage-only measurement; no package or reader was changed.",
    "packages": len(rows),
    "totals": {key: sum(row[key] for row in rows) for key in keys},
    "results": sorted(rows, key=lambda row: row["gross_saved"], reverse=True),
}
(notes / "payload-savings-checkpoint.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({key: value for key, value in report.items() if key != "results"}, indent=2))
print(json.dumps(report["results"][:8], indent=2))
