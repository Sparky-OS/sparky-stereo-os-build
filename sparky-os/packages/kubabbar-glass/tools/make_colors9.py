#!/usr/bin/env python3
"""Kubabbar Glass 9's colour schemes, one per accent variation (lavender first, the default), and the Plasma style's and
the Look and Feel's copies of the default. Every text colour reads at 4.5:1 or more on each background of its group
(Daniel, 2026-11-25: "yes, fix them. bring them to a readable level"); the script stops when one does not.
GPL-3.0-only."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from platinum9 import (ACCENTS, ACCENT_NAMES, DEFAULT_ACCENT, FACE, FACE_ALT, LANGUAGES, STYLE_OVERRIDES, TEXT,  # noqa: E402
                       TEXT_INACTIVE, TOOLTIP, VIEW, VIEW_ALT, contrast, scheme_id)

ROOT = Path(__file__).resolve().parents[1] / "share"
TARGET = 4.5

# the texts that do not change with the accent
LINK, VISITED = (0, 0, 192), (96, 32, 128)
NEGATIVE, NEUTRAL, POSITIVE = (160, 0, 0), (112, 72, 0), (0, 96, 0)
COMPLEMENTARY = {"BackgroundNormal": (51, 51, 51), "BackgroundAlternate": (64, 64, 64), "ForegroundNormal": (255, 255, 255),
                 "ForegroundInactive": (190, 190, 190), "ForegroundActive": (204, 204, 255),
                 "ForegroundLink": (153, 187, 255), "ForegroundVisited": (210, 160, 255),
                 "ForegroundNegative": (255, 140, 140), "ForegroundNeutral": (240, 200, 110),
                 "ForegroundPositive": (140, 220, 140)}


def rgb(c):
    return ",".join(str(v) for v in c)


def group(normal, alternate, accent, extra=None):
    g = {"BackgroundNormal": normal, "BackgroundAlternate": alternate, "ForegroundNormal": TEXT,
         "ForegroundInactive": TEXT_INACTIVE, "ForegroundActive": accent["dark"], "ForegroundLink": LINK,
         "ForegroundVisited": VISITED, "ForegroundNegative": NEGATIVE, "ForegroundNeutral": NEUTRAL,
         "ForegroundPositive": POSITIVE, "DecorationFocus": accent["accent"], "DecorationHover": accent["mid"]}
    g.update(extra or {})
    return g


def scheme(accent_name, overrides=None):
    a = ACCENTS[accent_name]
    groups = {
        "Window": group(FACE, FACE, a),
        "Button": group(FACE, FACE_ALT, a),
        "View": group(VIEW, VIEW_ALT, a),
        "Header": group(FACE, FACE, a),
        "Selection": group(a["light"], tuple(max(0, c - 14) for c in a["light"]), a,
                           {"ForegroundInactive": (56, 56, 56), "ForegroundPositive": (0, 80, 0),
                            "ForegroundNeutral": (96, 60, 0), "DecorationFocus": a["dark"]}),
        "Tooltip": group(TOOLTIP, (244, 244, 214), a),
        "Complementary": dict(COMPLEMENTARY, DecorationFocus=a["mid"], DecorationHover=a["light"]),
    }
    for (group_name, key), value in (overrides or {}).items():
        groups[group_name][key] = value
    bad = []
    for name, g in groups.items():
        for fk, fv in g.items():
            if not fk.startswith("Foreground"):
                continue
            for bk in ("BackgroundNormal", "BackgroundAlternate"):
                c = contrast(fv, g[bk])
                if c < TARGET:
                    bad.append(f"{accent_name} {name} {fk} on {bk}: {c:.2f}")
    if bad:
        sys.exit("texts under 4.5:1:\n" + "\n".join(bad))
    sid = scheme_id(accent_name)
    names = {lang: "Kubabbar Glass 9" + ("" if accent_name == DEFAULT_ACCENT else " " + ACCENT_NAMES[accent_name][lang])
             for lang in LANGUAGES}
    lines = ["[General]", f"Name={names['en']}"]
    lines += [f"Name[{lang}]={names[lang]}" for lang in LANGUAGES if lang != "en"]
    lines += [f"ColorScheme={sid}", "shadeSortColumn=true", "", "[KDE]", "contrast=7", "",
              "[ColorEffects:Disabled]", f"Color={rgb(FACE)}", "ColorAmount=0", "ColorEffect=0", "ContrastAmount=0.55",
              "ContrastEffect=1", "IntensityAmount=0", "IntensityEffect=0", "",
              "[ColorEffects:Inactive]", "Enable=false", "ChangeSelectionColor=true", ""]
    for name, g in groups.items():
        lines.append(f"[Colors:{name}]")
        lines += [f"{k}={rgb(v)}" for k, v in g.items()]
        lines.append("")
    lines += ["[WM]", f"activeBackground={rgb(FACE)}", f"activeForeground={rgb(TEXT)}", f"inactiveBackground={rgb(FACE)}",
              f"inactiveForeground={rgb(TEXT_INACTIVE)}", f"activeBlend={rgb(FACE)}", f"inactiveBlend={rgb(FACE)}"]
    return sid, "\n".join(lines) + "\n"


def main():
    out = ROOT / "color-schemes"
    out.mkdir(parents=True, exist_ok=True)
    default = None
    for accent_name in ACCENTS:
        sid, text = scheme(accent_name)
        (out / f"{sid}.colors").write_text(text)
        if accent_name == DEFAULT_ACCENT:
            default = text
    # the Look and Feel's copy (a Look and Feel without contents/colors does not apply its scheme, classic-look
    # milestone 2) and the Plasma style's colours, which take the texts readable over its translucent surfaces
    look = ROOT / "plasma/look-and-feel/kubabbar-glass-9/contents/colors"
    look.parent.mkdir(parents=True, exist_ok=True)
    look.write_text(default)
    style = ROOT / "plasma/desktoptheme/kubabbar-glass-9/colors"
    style.parent.mkdir(parents=True, exist_ok=True)
    style.write_text(scheme(DEFAULT_ACCENT, STYLE_OVERRIDES)[1])
    print("wrote", len(ACCENTS), "schemes")


if __name__ == "__main__":
    main()
