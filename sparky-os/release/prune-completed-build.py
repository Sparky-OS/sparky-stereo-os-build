#!/usr/bin/env python3
"""Remove only successful migration build trees after retaining their evidence."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
import tarfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

base = (cfg.path('SPARKY_MIGRATION_WORK') / 'jobs')
for name in sys.argv[1:]:
    if Path(name).name != name or not re.fullmatch(
        r"[a-z0-9][a-z0-9+.-]*-(?:amd64|i386|arm64)(?:-engine[0-9]+)?", name
    ):
        raise SystemExit("Expected a current or superseded successful migration job name")
    work = base / name
    source = work / "source"
    if source.is_symlink() or not source.is_dir():
        raise SystemExit(f"{name}: no ordinary source build tree")
    status = json.loads((work / "status.json").read_text())
    native = json.loads((work / "native-source.json").read_text())
    assert status["state"] == "candidate-needs-review" and status["exit_code"] == 0
    assert native["qualified"] and native["stage"] == "before compilation"
    descriptors = list(work.glob("*+lc1.dsc"))
    assert len(descriptors) == 1
    fields = next(stanzas(descriptors[0].read_text()))
    retained = {}
    for row in fields["checksums-sha256"].splitlines():
        if not row.strip():
            continue
        sha, size, filename = row.split()
        path = work / filename
        assert path.parent == work and path.stat().st_size == int(size)
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assert sha == digest, path
        retained[filename] = digest
    evidence = [
        descriptors[0].name, "native-source.json", "native-authored-evidence.tar.xz", "build.log"
    ]
    if status.get("resumed_after_disk_stop"):
        evidence += ["resume-build.log", "resume.sh", "disk-stop/status.json"]
    for filename in status["archives"] + evidence:
        path = work / filename
        assert path.is_file() and path.stat().st_size
        with path.open("rb") as stream:
            retained[filename] = hashlib.file_digest(stream, "sha256").hexdigest()
    with tarfile.open(work / "native-authored-evidence.tar.xz") as archive:
        assert ".sparky-lc/source.json" in archive.getnames()
    collector_path = Path(__file__).with_name('collect-compiler-inputs.py')
    spec = importlib.util.spec_from_file_location('compiler_input_evidence', collector_path)
    collector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(collector)
    collector.collect(source, work / 'compiler-input-evidence.json')
    test_archive = work / "test-evidence.tar.xz"
    assert not test_archive.exists(), "Do not replace earlier retained test evidence"
    tests = []
    with tarfile.open(test_archive, "x:xz") as archive:
        for path in sorted(source.rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(source)
            if (path.suffix in (".log", ".trs") or path.name == "CTestTestfile.cmake"
                    or "Testing" in relative.parts or "meson-logs" in relative.parts):
                archive.add(path, arcname=str(relative), recursive=False)
                tests.append(str(relative))
    record = {
        "source": str(source),
        "retained_archives_sha256": retained,
        "test_evidence": tests,
        "action": "remove disposable expanded build tree; source, packages and evidence retained",
    }
    (work / "build-tree-retention.json").write_text(json.dumps(record, indent=2) + "\n")
    shutil.rmtree(source)
    print(name, "removed expanded build tree; retained source and evidence", flush=True)
