#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: writes this folder's patches/ from the edition's Krita fork (queue row 148): every commit of BRANCH
# after BASE as git format-patch writes it, with DEP-3 fields added to its header: a commit carried from upstream
# ("(cherry picked from commit ...)") names its origin and where upstream has it; a commit of ours says why it is not
# forwarded (Krita's README sets a moratorium on AI-assisted contributions). patches/series lists them in order.
#   export-patches.py CLONE BASE BRANCH
#   CLONE   the Krita clone that holds BRANCH (invent.kde.org/danielcamposramos/krita)
#   BASE    the upstream tag the source package is (v6.0.4.1)
#   BRANCH  the branch (order148b-canvas-per-eye)
import re
import subprocess
import sys
import tempfile
from pathlib import Path

UPSTREAM = "https://invent.kde.org/graphics/krita/-/commit/"
# where upstream has each carried commit (read on invent.kde.org, 2026-11-26)
APPLIED = {
    "30182dbfe789c9b44e5762978bf9ebb22c4f72b6": "master (before Krita 6.1)",
    "bf7fa438058f95df35d98da73f6ba8b6751c01d4": "master (before Krita 6.1)",
    "cd9449141933438eebefd47bbe5e4359edabba07": "krita/6.0 (Krita 6.0.6) and master",
}
OURS = ("Forwarded: no, Krita's README sets a moratorium on AI-assisted contributions; carried in the edition's fork,\n"
        " https://invent.kde.org/danielcamposramos/krita\n")


def main():
    clone, base, branch = sys.argv[1:4]
    here = Path(__file__).resolve().parent
    out = here / "patches"
    out.mkdir(exist_ok=True)
    for old in out.glob("*.patch"):
        old.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["git", "-C", clone, "format-patch", "--quiet", "--no-signature", "-o", tmp, f"{base}..{branch}"],
                       check=True)
        names = []
        for path in sorted(Path(tmp).glob("*.patch")):
            text = path.read_text(encoding="utf-8")
            head, sep, rest = text.partition("\n\n")
            picked = re.search(r"\(cherry picked from commit ([0-9a-f]{40})\)", rest)
            if picked:
                sha = picked.group(1)
                fields = f"Origin: upstream, {UPSTREAM}{sha}\nApplied-Upstream: {APPLIED[sha]}, {UPSTREAM}{sha}\n"
            else:
                fields = OURS
            (out / path.name).write_text(head + "\n" + fields.rstrip("\n") + sep + rest, encoding="utf-8")
            names.append(path.name)
    (out / "series").write_text("".join(n + "\n" for n in names))
    print("\n".join(names))


if __name__ == "__main__":
    main()
