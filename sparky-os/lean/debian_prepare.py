# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Add reproducible Lean Code stages to a disposable, conventional dh source tree.

This is intentionally a checked preparation step, not an unrestricted rules
rewriter. Custom packaging hooks require their own reviewed integration.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


TARGETS = (
    "execute_before_dh_auto_configure",
    "execute_before_dh_auto_clean",
    "override_dh_builddeb",
)


def prepare(root, version, toolkit, build_dependencies=(), preserve_sources=()):
    root, toolkit = Path(root).resolve(), Path(toolkit).resolve()
    rules_path = root / "debian/rules"
    rules = rules_path.read_text()
    if not re.search(r"^\s*dh\s+[\"']?\$@", rules, re.M):
        raise ValueError("Not a conventional dh rules file; integrate its builder explicitly")
    for target in TARGETS:
        if re.search(r"^" + re.escape(target) + r"(?:-arch|-indep)?\s*:", rules, re.M):
            raise ValueError(f"Existing {target}: preserve and integrate its behavior explicitly")
    if "sparky-lean-toolkit" in rules:
        raise ValueError("Source is already integrated")
    old = subprocess.check_output(
        ["dpkg-parsechangelog", "-S", "Version"], cwd=root, text=True
    ).strip()
    if subprocess.run(["dpkg", "--compare-versions", version, "gt", old]).returncode:
        raise ValueError("The migration must advance the package version")
    destination = root / "debian/sparky-lean-toolkit"
    if destination.exists():
        raise ValueError("Refusing to replace an existing toolkit")
    preserve = {}
    for pattern, reason in preserve_sources:
        if (not pattern or pattern.startswith('/') or '..' in pattern.split('/')
                or '\\' in pattern or not reason.strip() or pattern in preserve):
            raise ValueError("Source preservation needs unique safe relative patterns and reasons")
        preserve[pattern] = reason
    preserve_path = root / 'debian/sparky-lean-preserve.json'
    if preserve and preserve_path.exists():
        raise ValueError("Preserve the existing source-consumer plan; do not replace it")

    # Check all inputs before modifying the disposable source.
    for required in ("lean/source_tree.py", "lean/debhelper.py", "repo/provenance.sh",
                     "packages/dpkg-stereo/LICENSE"):
        if not (toolkit / required).is_file():
            raise ValueError(f"Missing toolkit input: {required}")
    control_path = root / "debian/control"
    control = control_path.read_text()
    first, separator, rest = control.partition("\n\n")
    dependencies = ["gcc", "node-acorn", "nodejs", "perl", "python3", "python3-yaml"]
    for dependency in build_dependencies:
        if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+(?: <!nocheck>)?", dependency):
            raise ValueError(f"Unsupported additional build dependency: {dependency!r}")
        dependencies.append(dependency)
    match = re.search(r"^Build-Depends:\s*(.*(?:\n[ \t].*)*)", first, re.M)
    if match:
        existing = match.group(1)
        additions = [dep for dep in dependencies
                     if not re.search(r"(?:^|[,\s])" + re.escape(dep) + r"(?:[,\s(]|$)", existing)]
        if additions:
            joining = " " if existing.rstrip().endswith(",") else ", "
            first = first[:match.end()] + joining + ", ".join(additions) + first[match.end():]
    else:
        first += "\nBuild-Depends: " + ", ".join(dependencies)

    (destination / "lean").mkdir(parents=True)
    for path in (toolkit / "lean").glob("*.py"):
        shutil.copy2(path, destination / "lean" / path.name)
    shutil.copy2(toolkit / "lean/JvmLexer.java", destination / "lean/JvmLexer.java")
    shutil.copy2(toolkit / "repo/provenance.sh", destination / "provenance.sh")
    shutil.copy2(toolkit / "packages/dpkg-stereo/LICENSE", destination / "LICENSE")
    control_path.write_text(first + separator + rest)
    if preserve:
        preserve_path.write_text(json.dumps(preserve, indent=2) + '\n')
    subprocess.run([
        "dch", "--newversion", version, "--distribution", "UNRELEASED",
        "Apply verified native Lean Code before compilation and qualified lc1 "
        "payload assembly; retain exact authored source and HR companions.",
    ], cwd=root, check=True)
    rules_path.write_text(rules.rstrip() + """

# Distribution-only processing; authored source remains in the source archive.
execute_before_dh_auto_configure:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)

execute_before_dh_auto_clean:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)
\trm -rf .sparky-lc

override_dh_builddeb:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance $(CURDIR)/debian/sparky-lean-toolkit/provenance.sh
""")
    print(f"Prepared {root.name}: {old} -> {version}; native and payload stages retained in source")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("version")
    parser.add_argument("--toolkit", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--build-dependency", action="append", default=[],
                        help="Reviewed build prerequisite to retain in the source control file")
    parser.add_argument("--preserve-source", nargs=2, action="append", default=[],
                        metavar=("PATTERN", "REASON"),
                        help="Keep source read by an additional consumer unchanged; retained in source")
    args = parser.parse_args()
    try:
        prepare(args.root, args.version, args.toolkit, args.build_dependency, args.preserve_source)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
