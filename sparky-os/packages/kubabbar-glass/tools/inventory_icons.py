#!/usr/bin/env python3
"""Inventory installed artwork without copying it or inferring rights from names."""
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

ROOTS = {
    "oxygen": Path("/usr/share/icons/oxygen"),
    "gnome": Path("/usr/share/icons/gnome"),
    "Adwaita": Path("/usr/share/icons/Adwaita"),
    "sparkyblack": Path("/usr/share/icons/sparkyblack"),
    "NineIcons48x": Path("/home/daniel/.local/share/icons/NineIcons48x"),
    "Glass": Path("/home/daniel/.local/share/icons/Glass"),
}
LICENSES = {
    "oxygen": "LGPL-3.0-or-later",
    "gnome": "GPL-2.0-or-later",
    "Adwaita": "(CC-BY-SA-3.0 OR LGPL-3.0-only) AND CC-BY-SA-4.0; inspect per-file scope before redistribution",
}
EXTENSIONS = {".png", ".svg", ".svgz", ".xpm", ".ico"}


def scan(theme, root):
    rows = []
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() not in EXTENSIONS:
            continue
        resolved = path.resolve()
        row = {"theme": theme, "path": str(path.relative_to(root)),
               "name": path.stem, "symlink": str(path.readlink()) if path.is_symlink() else "",
               "sha256": "", "read_status": "ok"}
        if not any(resolved.is_relative_to(r) for r in ROOTS.values()):
            row["read_status"] = "outside-audited-roots"
        elif not resolved.is_file():
            row["read_status"] = "broken-link"
        else:
            row["sha256"] = hashlib.sha256(resolved.read_bytes()).hexdigest()
        rows.append(row)
    return rows


def main():
    out = Path(__file__).resolve().parents[1] / "study"
    all_rows = {name: scan(name, root) for name, root in ROOTS.items()}
    known = defaultdict(list)
    for theme in LICENSES:
        for row in all_rows[theme]:
            if row["sha256"]:
                known[row["sha256"]].append(row)
    oxygen_names = {r["name"] for r in all_rows["oxygen"] if r["sha256"]}
    inventory = []
    for theme in ("sparkyblack", "NineIcons48x", "Glass"):
        for row in all_rows[theme]:
            matches = known.get(row["sha256"], [])
            row["absent_from_oxygen_by_name"] = str(row["name"] not in oxygen_names).lower()
            row["known_identical_sources"] = " | ".join(f'{r["theme"]}/{r["path"]}' for r in matches)
            row["source_licences"] = " | ".join(LICENSES[t] for t in dict.fromkeys(r["theme"] for r in matches))
            row["disposition"] = "use-packaged-source" if matches else "unresolved-exclude"
            if theme == "Glass":
                row["disposition"] = "exclude-Glass-no-redistribution"
            inventory.append(row)
    fields = list(inventory[0])
    with (out / "icon-inventory.csv").open("w") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(inventory)
    with (out / "sparky-missing-from-oxygen.txt").open("w") as f:
        f.write("\n".join(sorted({r["name"] for r in inventory if r["theme"] == "sparkyblack" and r["absent_from_oxygen_by_name"] == "true"})) + "\n")
    summary = {}
    for theme, rows in all_rows.items():
        summary[theme] = {"files": len(rows), "unique_names": len({r["name"] for r in rows}),
                          "read_status": dict(Counter(r["read_status"] for r in rows))}
        if theme not in LICENSES:
            selected = [r for r in inventory if r["theme"] == theme]
            summary[theme]["disposition"] = dict(Counter(r["disposition"] for r in selected))
            summary[theme]["names_absent_from_oxygen"] = len({r["name"] for r in selected if r["absent_from_oxygen_by_name"] == "true"})
            summary[theme]["identical_to"] = {t: sum(any(m["theme"] == t for m in known.get(r["sha256"], [])) for r in selected) for t in LICENSES}
    (out / "icon-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
