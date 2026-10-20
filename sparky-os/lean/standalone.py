# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Seal authored script/data staging and retain a rebuildable Debian source package.

This adapter accepts architecture-independent packages without compiled programs.
Native binaries must use their native source build and its pre-compilation proof.
"""
import argparse
import email.utils
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

from . import package, release


def normalize_modes(tree):
    # Source extraction may make directories group-writable regardless of the
    # archive modes. Apply the same staging policy on initial and source builds.
    for path in (tree, *tree.rglob("*")):
        if not path.is_symlink():
            path.chmod(stat.S_IMODE(path.stat().st_mode) & ~0o022)


def build(tree, out, authoring):
    old_umask = os.umask(0o022)
    try:
        return _build(tree, out, authoring)
    finally:
        os.umask(old_umask)


def _build(tree, out, authoring):
    tree, out, authoring = (Path(p).resolve() for p in (tree, out, authoring))
    fields = package.control(tree)
    name, version, arch = package.identity(fields)
    if arch != "all" or "-" in version or ":" in version:
        raise ValueError("This adapter requires an architecture-all native source package")
    if fields.get("source", name) not in (name, f"{name} ({version})"):
        raise ValueError("Keep a multi-binary source under its original source build")
    normalize_modes(tree)
    for path in tree.rglob("*"):
        if path.is_symlink():
            continue
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic in (b"\x7fELF", b"\x00asm") or magic[:2] == b"MZ":
            raise ValueError(f"{path}: compiled payload requires native build evidence")
    out.mkdir(parents=True, exist_ok=True)
    for suffix in ("dsc", "tar.xz"):
        if (out / f"{name}_{version}.{suffix}").exists():
            raise ValueError("Source output exists; use a fresh version or isolated output")
    toolkit = Path(__file__).resolve().parent.parent
    provenance = toolkit / "repo/provenance.sh"
    if not provenance.exists():
        provenance = toolkit / "provenance.sh"
    subprocess.run(["bash", str(provenance), "--tree", str(tree)], check=True)
    with tempfile.TemporaryDirectory(prefix="lc-script-source-", dir=out) as temporary:
        work = Path(temporary)
        source = work / f"{name}-{version}"
        (source / "debian/source").mkdir(parents=True)
        shutil.copytree(tree, source / "tree", symlinks=True)
        shutil.copytree(authoring, source / "authoring",
                        symlinks=True,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"))
        kit = source / "release-toolkit"
        (kit / "lean").mkdir(parents=True)
        for path in (toolkit / "lean").glob("*.py"):
            shutil.copy2(path, kit / "lean" / path.name)
        shutil.copy2(toolkit / "lean/JvmLexer.java", kit / "lean/JvmLexer.java")
        licence = toolkit / "packages/dpkg-stereo/LICENSE"
        if not licence.exists():
            licence = toolkit / "LICENSE"
        shutil.copy2(licence, kit / "LICENSE")
        section, priority = fields.get("section", "misc"), fields.get("priority", "optional")
        maintainer = fields["maintainer"]
        (source / "debian/control").write_text(
            f"Source: {name}\nSection: {section}\nPriority: {priority}\n"
            f"Maintainer: {maintainer}\n"
            "Build-Depends: dpkg-dev, gcc, node-acorn, nodejs, perl, python3, python3-yaml\n"
            "Standards-Version: 4.7.4\nRules-Requires-Root: no\n\n"
            f"Package: {name}\nArchitecture: all\nSection: {section}\nPriority: {priority}\n"
            f"Description: {fields['description']}\n"
        )
        (source / "debian/changelog").write_text(
            f"{name} ({version}) unstable; urgency=medium\n\n"
            "  * Build from retained authored staging and generator inputs; apply\n"
            "    qualified Lean Code and publish matching HR documentation.\n\n"
            f" -- {maintainer}  {email.utils.formatdate(localtime=False)}\n"
        )
        (source / "debian/source/format").write_text("3.0 (native)\n")
        shutil.copy2(tree / f"usr/share/doc/{name}/copyright", source / "debian/copyright")
        (source / "README.source").write_text(
            "tree/ is the complete authored, pre-projection staging tree, including\n"
            "maintainer scripts and controls. authoring/ retains the original builder\n"
            "and its inputs. No payload was recovered from a binary archive.\n"
            "The source rebuild uses tree/ so external paths or later workspace\n"
            "changes cannot change the resolved payload. release-toolkit/ contains\n"
            "the exact qualified renderer; native compiled binaries are not accepted\n"
            "by this script/data adapter.\n"
        )
        (source / "build.py").write_text('''#!/usr/bin/env python3
from pathlib import Path
import os, shutil, subprocess, sys, tempfile
os.umask(0o022)
root = Path(__file__).resolve().parent
sys.path.insert(0, str(root / "release-toolkit"))
from lean import package, release
from lean.standalone import normalize_modes
with tempfile.TemporaryDirectory(dir=root, prefix=".staging-") as work:
    staging = Path(work) / "tree"
    shutil.copytree(root / "tree", staging, symlinks=True)
    normalize_modes(staging)
    before = set(root.parent.glob("*.deb"))
    release.build_tree(staging, root.parent)
    for archive in sorted(set(root.parent.glob("*.deb")) - before):
        fields = next(package.stanzas(subprocess.check_output(["dpkg-deb", "-f", str(archive)], text=True)))
        subprocess.run(["dpkg-distaddfile", archive.name, fields.get("section", "misc"),
                        fields.get("priority", "optional")], check=True)
        if fields["package"].endswith("-lc-hr"):
            index = root / "debian/files"
            index.write_text("".join(line + (" automatic=yes" if line.split()[0] == archive.name else "") + "\\n"
                                     for line in index.read_text().splitlines()))
''')
        # Binary controls in the authored tree supply the exact dependencies.
        rules = source / "debian/rules"
        rules.write_text("#!/usr/bin/make -f\nbinary binary-indep:\n\tpython3 build.py\n"
                         "binary-arch build build-arch build-indep clean:\n"
                         ".PHONY: binary binary-arch binary-indep build build-arch build-indep clean\n")
        rules.chmod(0o755)
        subprocess.run(["dpkg-source", "-b", str(source)], cwd=work, check=True)
        release.build_tree(tree, out)
        for suffix in ("dsc", "tar.xz"):
            shutil.copy2(work / f"{name}_{version}.{suffix}", out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tree", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--authoring", required=True, type=Path)
    args = parser.parse_args()
    try:
        build(args.tree, args.out, args.authoring)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
