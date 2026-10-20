# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Check that custom-builder integration preserves the authored recipe."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from lean.debian_custom import integrate


BUILDER = '''#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?}
VERSION=1
PACKAGE=lean-fixture
D=$OUT/payload
mkdir -p "$D"
cp "$HERE/source.c" "$D/source.c"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_amd64.deb"
S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
'''


@unittest.skipUnless(shutil.which("dch") and shutil.which("dpkg-parsechangelog"),
                     "Debian source tools required")
class CustomBuilderTests(unittest.TestCase):
    def fixture(self, root, builder=BUILDER):
        (root / "debian").mkdir()
        (root / "build.sh").write_text(builder)
        (root / "debian/rules").write_text("#!/usr/bin/make -f\nbinary:\n\tbash build.sh\n")
        (root / "debian/control").write_text(
            "Source: lean-fixture\nBuild-Depends: dpkg-dev\n\n"
            "Package: lean-fixture\nArchitecture: any\nDescription: test fixture\n")
        (root / "debian/changelog").write_text(
            "lean-fixture (1) unstable; urgency=medium\n\n  * Fixture.\n\n"
            " -- Example <example@example.invalid>  Tue, 20 Oct 2026 10:00:00 +0000\n")

    def test_recipe_source_and_declared_dependency_survive_integration(self):
        toolkit = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            authored_rules = (root / "debian/rules").read_bytes()
            with patch.dict(os.environ, {"DEBFULLNAME": "Example",
                                        "DEBEMAIL": "example@example.invalid"}):
                integrate(root, "1+lc1", toolkit, ["qt6-declarative-dev"])
            self.assertEqual((root / "build.sh").read_text(), BUILDER)
            self.assertEqual((root / "debian/rules.before-lean").read_bytes(), authored_rules)
            self.assertIn("qt6-declarative-dev", (root / "debian/control").read_text())
            generated = (root / "debian/lean-build.sh").read_text()
            subprocess.run(["bash", "-n"], input=generated, text=True, check=True)
            self.assertIn('cp "$HERE/source.c" "$D/source.c"', generated)
            self.assertIn("VERSION=1+lc1\n", generated)
            self.assertNotIn("dpkg-deb --root-owner-group", generated)
            self.assertNotIn("S=$WORK/", generated)
            self.assertIn("lean.source_tree restore-payload", generated)
            self.assertIn("lean.release build-tree", generated)
            with self.assertRaises(ValueError):
                integrate(root, "1+lc2", toolkit)

    def test_unreviewed_build_shapes_are_rejected_before_edits(self):
        variants = [
            BUILDER.replace('cp "$HERE/source.c"', 'dpkg-deb -b "$D" early.deb\ncp "$HERE/source.c"'),
            BUILDER.replace("S=$WORK/$PACKAGE-$VERSION", "echo unrelated post-processing"),
            BUILDER.replace("set -euo pipefail", "set -e"),
            BUILDER.replace("PACKAGE=lean-fixture", "PACKAGE=other"),
        ]
        toolkit = Path(__file__).resolve().parents[2]
        for builder in variants:
            with self.subTest(builder=builder), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root, builder)
                before = {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    integrate(root, "1+lc1", toolkit)
                after = {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}
                self.assertEqual(before, after)
