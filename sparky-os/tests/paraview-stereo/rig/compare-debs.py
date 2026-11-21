#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""compare-debs.py DEBIAN_DIR OURS_DIR WORK OUT.txt [PACKAGE...]

Each binary package of ours in OURS_DIR (not -dbgsym, not -lc-hr) against Debian's of the same name in DEBIAN_DIR, file by
file: the paths only in one of them; owner, mode, link target; and every regular file's bytes, sorted into
  same          the same bytes
  projected     ours is Lean Code's projection of Debian's exact bytes (its lc1 manifest gives Debian's SHA-256 as sha_hr)
  elf           an ELF file rebuilt: NEEDED, SONAME and the defined dynamic symbols compared
  changelog/copyright, and every other difference listed by path.
Then the control fields that differ. The extracted trees go under WORK (removed after each package).
Prints a summary; the full lists go to OUT.txt."""
import hashlib, json, os, shutil, subprocess, sys
from pathlib import Path

deb_dir, ours_dir, work, out_path = map(Path, sys.argv[1:5])
only = set(sys.argv[5:])
PREV = os.environ.get("PREV_LABEL", "Debian's")


def field(deb, name):
    r = subprocess.run(["dpkg-deb", "-f", str(deb), name], capture_output=True, text=True)
    return r.stdout.strip()


def listing(deb):
    r = subprocess.run(["dpkg-deb", "-c", str(deb)], capture_output=True, text=True, check=True)
    entries = {}
    for line in r.stdout.splitlines():
        parts = line.split(None, 5)
        perm, owner, size, _date, _time, rest = parts
        link = ""
        if " -> " in rest:
            rest, link = rest.split(" -> ", 1)
        entries[rest.rstrip("/")] = (perm, owner, int(size), link)
    return entries


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def elf_facts(path):
    d = subprocess.run(["readelf", "-dW", str(path)], capture_output=True, text=True).stdout
    needed = sorted(l.split("[", 1)[1].rstrip("]") for l in d.splitlines() if "(NEEDED)" in l)
    soname = [l.split("[", 1)[1].rstrip("]") for l in d.splitlines() if "(SONAME)" in l]
    s = subprocess.run(["nm", "-D", "--defined-only", str(path)], capture_output=True, text=True).stdout
    syms = sorted(set(l.split()[-1] for l in s.splitlines() if l.strip()))
    return needed, soname, syms


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def manifest(root):
    m = {}
    base = root / "usr/share/dpkg-stereo/lc"
    if base.is_dir():
        for j in base.glob("*/*.json"):
            for e in json.load(open(j)).get("files", []):
                m[e["path"]] = e
    return m


debs = {}
for d in sorted(deb_dir.glob("*.deb")):
    debs[field(d, "Package")] = d
report = []
summary = []
for ours in sorted(ours_dir.glob("*.deb")):
    name = field(ours, "Package")
    if name.endswith("-dbgsym") or name.endswith("-lc-hr") or (only and name not in only):
        continue
    theirs = debs.get(name)
    if not theirs:
        summary.append(f"{name}: no package of that name in Debian's set")
        continue
    a, b = listing(theirs), listing(ours)
    gone = sorted(set(a) - set(b))
    added = sorted(set(b) - set(a))
    meta = [(p, a[p][:2] + (a[p][3],), b[p][:2] + (b[p][3],)) for p in sorted(set(a) & set(b))
            if (a[p][0], a[p][1], a[p][3]) != (b[p][0], b[p][1], b[p][3])]
    ta, tb = work / ("debian-" + name), work / ("ours-" + name)
    for t in (ta, tb):
        shutil.rmtree(t, ignore_errors=True)
        t.mkdir(parents=True)
    subprocess.run(["dpkg-deb", "-x", str(theirs), str(ta)], check=True)
    subprocess.run(["dpkg-deb", "-x", str(ours), str(tb)], check=True)
    lc = manifest(tb)
    cls = {"same": [], "projected": [], "elf-same-interface": [], "elf-interface-differs": [], "doc": [], "other": []}
    for p in sorted(set(a) & set(b)):
        if not a[p][0].startswith("-"):
            continue
        fa, fb = ta / p, tb / p
        if not (fa.is_file() and fb.is_file()):
            continue
        ha, hb = sha(fa), sha(fb)
        path = p.lstrip(".")
        if ha == hb:
            cls["same"].append(path)
        elif path in lc and lc[path].get("status") == "projected" and lc[path].get("sha_hr") == ha and lc[path].get("sha256") == hb:
            cls["projected"].append(path)
        elif is_elf(fa) and is_elf(fb):
            fa_, fb_ = elf_facts(fa), elf_facts(fb)
            if fa_ == fb_:
                cls["elf-same-interface"].append(path)
            else:
                na, sa, ya = fa_; nb, sb, yb = fb_
                cls["elf-interface-differs"].append(
                    f"{path}: NEEDED -{sorted(set(na)-set(nb))} +{sorted(set(nb)-set(na))}; SONAME {sa}->{sb}; "
                    f"symbols -{len(set(ya)-set(yb))} +{len(set(yb)-set(ya))} {sorted(set(yb)-set(ya))[:8]} {sorted(set(ya)-set(yb))[:8]}")
        elif path.endswith(("/changelog.Debian.gz", "/copyright")):
            cls["doc"].append(path)
        else:
            cls["other"].append(path)
    fields = []
    for f in ("Version", "Maintainer", "Original-Maintainer", "Homepage", "Bugs", "Depends", "Pre-Depends", "Recommends",
              "Suggests", "Breaks", "Replaces", "Conflicts", "Provides", "Installed-Size", "Multi-Arch", "Section"):
        va, vb = field(theirs, f), field(ours, f)
        if va != vb:
            fields.append(f"{f}: {PREV} [{va}] -> ours [{vb}]")
    summary.append(f"{name}: {len(a)} paths in {PREV}, {len(b)} in ours; left {len(gone)}, added {len(added)}, "
                   f"owner/mode/link differ {len(meta)}; files: " + ", ".join(f"{k} {len(v)}" for k, v in cls.items()))
    report.append(f"== {name}: {theirs.name} -> {ours.name}")
    report.append(f"left (only in {PREV}): {gone}")
    report.append(f"added (only in ours): {added}")
    report.append(f"owner/mode/link differ: {meta}")
    for k, v in cls.items():
        report.append(f"{k} ({len(v)}): " + (json.dumps(v) if k != "same" else "(not listed)"))
    report.extend(fields)
    report.append("")
    for t in (ta, tb):
        shutil.rmtree(t, ignore_errors=True)
out_path.write_text("\n".join(summary) + "\n\n" + "\n".join(report) + "\n")
print("\n".join(summary))
