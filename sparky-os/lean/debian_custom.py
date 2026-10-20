# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Integrate the edition's explicit build.sh staging convention into Debian builds.

The original authored builder remains untouched. This adapter accepts only its
known HERE/VERSION/PACKAGE and single final dpkg-deb invocation, not arbitrary
shell programs. Generated source-packaging tails are replaced by dpkg's normal
source-before-binary lifecycle.
"""
import argparse
from pathlib import Path
import re
import subprocess

from .debian_prepare import prepare


def integrate(root, version, toolkit, build_dependencies=()):
    root = Path(root).resolve()
    if not re.fullmatch(r"[0-9][A-Za-z0-9.+:~\-]*", version):
        raise ValueError("Expected a literal Debian version")
    source = root / "build.sh"
    original = source.read_text()
    package = subprocess.check_output(
        ["dpkg-parsechangelog", "-S", "Source"], cwd=root, text=True
    ).strip()
    if not re.search(r"^PACKAGE=" + re.escape(package) + r"$", original, re.M):
        raise ValueError("Builder PACKAGE must match the source package")
    here = 'HERE=$(cd "$(dirname "$0")" && pwd)'
    if original.count(here) != 1:
        raise ValueError("Unknown builder source-directory convention")
    assembly = list(re.finditer(
        r'^dpkg-deb --root-owner-group -Zxz -b "\$D" "\$OUT/\$\{PACKAGE\}_\$\{VERSION\}_[^"\n]+"\s*$',
        original, re.M))
    if len(assembly) != 1:
        raise ValueError("Expected one reviewed final staging-tree assembly command")
    stage = original[:assembly[0].start()]
    if re.search(r"^\s*dpkg-deb\b", stage, re.M):
        raise ValueError("An earlier assembly command needs explicit integration")
    tail = original[assembly[0].end():].lstrip()
    if not re.match(r"S=\$(?:W|WORK)/\$PACKAGE-\$VERSION\n", tail):
        raise ValueError("Unknown post-assembly source-packaging convention")
    if stage.count("set -euo pipefail") != 1:
        raise ValueError("Expected the reviewed strict-shell build convention")
    if len(re.findall(r"^VERSION=\S+$", stage, re.M)) != 1:
        raise ValueError("Expected one literal VERSION assignment")
    stage = stage.replace(here, 'HERE=$(cd "$(dirname "$0")/.." && pwd)')
    stage = re.sub(r"^VERSION=\S+$", "VERSION=" + version, stage, flags=re.M)
    stage = stage.replace("set -euo pipefail", "set -euo pipefail\numask 022", 1)
    stage += '''
PYTHONPATH="$HERE/debian/sparky-lean-toolkit" python3 -m lean.source_tree restore-payload "$HERE" "$D"
bash "$HERE/debian/sparky-lean-toolkit/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/debian/sparky-lean-toolkit" python3 -m lean.release build-tree "$D" "$OUT"
'''
    subprocess.run(["bash", "-n"], input=stage, text=True, check=True)
    rules = root / "debian/rules"
    saved = rules.with_name("rules.before-lean")
    generated = root / "debian/lean-build.sh"
    if saved.exists() or generated.exists():
        raise ValueError("Custom builder is already integrated")
    # The shared preparation step qualifies dependencies, version and toolkit.
    # Its temporary conventional rules never run; the actual recipe below
    # retains the original builder's compilation and installation commands.
    saved.write_bytes(rules.read_bytes())
    rules.write_text("#!/usr/bin/make -f\n%:\n\tdh $@\n")
    try:
        prepare(root, version, toolkit, build_dependencies=build_dependencies)
    except Exception:
        rules.write_bytes(saved.read_bytes())
        raise
    generated.write_text(stage)
    rules.write_text("""#!/usr/bin/make -f

binary binary-arch binary-indep:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)
\tOUT=$(CURDIR)/.. bash debian/lean-build.sh
\tdpkg-distaddfile {package}_{version}_$$(dpkg --print-architecture).deb System optional
\tif test -f ../{package}-lc-hr_{version}_$$(dpkg --print-architecture).deb; then dpkg-distaddfile {package}-lc-hr_{version}_$$(dpkg --print-architecture).deb doc optional; sed -i '/^{package}-lc-hr_/s/$$/ automatic=yes/' debian/files; fi

clean:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)
\trm -rf .sparky-lc

build build-arch build-indep:
.PHONY: binary binary-arch binary-indep clean build build-arch build-indep
""".format(package=package, version=version.split(":", 1)[-1]))
    print(f"Integrated authored build.sh for {package}; original retained unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("version")
    parser.add_argument("--toolkit", type=Path, required=True)
    parser.add_argument("--build-dependency", action="append", default=[],
                        help="Additional source build dependency recorded in debian/control")
    args = parser.parse_args()
    try:
        integrate(args.root, args.version, args.toolkit, args.build_dependency)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
