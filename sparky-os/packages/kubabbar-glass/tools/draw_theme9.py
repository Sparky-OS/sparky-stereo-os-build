#!/usr/bin/env python3
"""Kubabbar Glass 9's window frame (a pinstriped active title bar, a plain inactive one), its buttons in the family's
square-box form, its Plasma style at the family's glass (glass_levels.py) and its wallpaper; with their metadata in the
ten languages. Original geometric artwork, GPL-3.0-only."""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from draw_theme import BUTTON_NAMES, BUTTON_STATES, glyph  # noqa: E402  the family's signs in the buttons
from glass_levels import SPARKY_BLACK_ALPHA, level  # noqa: E402
from platinum9 import FACE, LANGUAGES, LIGHT, OUTLINE, SHADOW, WALLPAPER, hexa  # noqa: E402
from strings9 import DECORATION_COMMENT, STYLE_DESCRIPTION, WALLPAPER_DESCRIPTION  # noqa: E402

ROOT = Path(__file__).resolve().parents[1] / "share"
ID = "kubabbar-glass-9"
DECO = ROOT / "aurorae/themes" / ID
PLASMA = ROOT / "plasma/desktoptheme" / ID
NS = 'xmlns="http://www.w3.org/2000/svg"'
AUTHORS = [{"Name": "Daniel Ramos and EchoSystems AI studios"}]


def save(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def rect(x, y, w, h, colour, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{colour}" {extra}/>'


def window_frame(prefix, y0, active):
    """The window frame's nine pieces: an outer outline, a light and a shadow edge, the face, and a dark line around the
    content; the title piece is 28 pixels with horizontal pinstripes when the window is active."""
    b, top, size = 4, 28, 64
    outline = hexa(OUTLINE) if active else "#7a7a7a"
    inner = "#3c3c3c" if active else "#969696"
    face, light, shadow = hexa(FACE), hexa(LIGHT), hexa(SHADOW)
    pieces = {"topleft": (0, y0, b, top), "top": (b, y0, size, top), "topright": (b + size, y0, b, top),
              "left": (0, y0 + top, b, size), "center": (b, y0 + top, size, size), "right": (b + size, y0 + top, b, size),
              "bottomleft": (0, y0 + top + size, b, b), "bottom": (b, y0 + top + size, size, b),
              "bottomright": (b + size, y0 + top + size, b, b)}
    chunks = []
    for part, (x, y, w, h) in pieces.items():
        ident = f"{prefix}-{part}"
        if part == "center":
            chunks.append(f'<g id="{ident}">{rect(x, y, w, h, face, "opacity=\"0\"")}</g>')
            continue
        body = rect(x, y, w, h, face)
        if "top" in part:
            body += rect(x, y, w, 1, outline) + rect(x, y + 1, w, 1, light)
            body += rect(x, y + h - 1, w, 1, inner)                       # the line under the title bar
            if active and part == "top":
                for row in range(6, 22, 2):
                    body += rect(x, y + row, w, 1, "#aaaaaa") + rect(x, y + row + 1, w, 1, light)
        if part in ("left", "bottomleft", "topleft"):
            body += rect(x, y, 1, h, outline) + rect(x + 1, y + (2 if "top" in part else 0), 1, h - (3 if "top" in part else 0), light)
        if part in ("right", "bottomright", "topright"):
            body += rect(x + w - 2, y + (1 if "top" in part else 0), 1, h - (1 if "top" in part else 0), shadow)
            body += rect(x + w - 1, y, 1, h, outline)
        if part in ("bottom", "bottomleft", "bottomright"):
            body += rect(x, y + h - 2, w, 1, shadow) + rect(x, y + h - 1, w, 1, outline)
        if part == "left":
            body += rect(x + w - 1, y, 1, h, inner)
        if part == "right":
            body += rect(x, y, 1, h, inner)
        if part == "bottom":
            body += rect(x, y, w, 1, inner)
        if part == "bottomleft":
            body += rect(x + w - 1, y, 1, 1, inner)
        if part == "bottomright":
            body += rect(x, y, 1, 1, inner)
        chunks.append(f'<g id="{ident}">{body}</g>')
    return "\n".join(chunks)


def button(name):
    """A square box with a bevel, the family's sign in it; pressed, the bevel turns in."""
    chunks = []
    for toggled in (False, True):
        for idx, state in enumerate(BUTTON_STATES):
            slot = idx * 22 + (176 if toggled else 0)
            pressed, hover = "pressed" in state, "hover" in state
            dead = state in ("inactive", "deactivated", "deactivated-inactive")
            face = "#888888" if pressed else "#eeeeee" if hover else hexa(FACE)
            tl, br = ("#666666", "#bbbbbb") if pressed else (hexa(LIGHT), hexa(SHADOW))
            line = "#969696" if dead else hexa(OUTLINE)
            body = (f'<rect x="{slot + .5}" y=".5" width="15" height="15" rx="1.5" fill="{face}" stroke="{line}"/>'
                    f'<path d="M{slot + 2} 13.5V2h11.5" stroke="{tl}" fill="none"/>'
                    f'<path d="M{slot + 2.5} 14H14V2.5" stroke="{br}" fill="none"/>')
            ink = "#9a9a9a" if dead else "#1e1e1e"
            body += glyph(name, slot, ink, face, toggled)
            chunks.append(f'<g id="{"on-" if toggled else ""}{state}-center">{body}</g>')
    save(DECO / f"{name}.svg", f'<svg {NS} width="352" height="16">' + "".join(chunks) + "</svg>\n")


def plasma_frame(prefix, y, alpha):
    """A Plasma frame piece set in the classic greys: an outline, a light and a shadow edge, the face; the whole group at
    the family's glass level."""
    b, size = 4, 64
    pieces = {"topleft": (0, y, b, b), "top": (b, y, size, b), "topright": (b + size, y, b, b), "left": (0, y + b, b, size),
              "center": (b, y + b, size, size), "right": (b + size, y + b, b, size), "bottomleft": (0, y + b + size, b, b),
              "bottom": (b, y + b + size, size, b), "bottomright": (b + size, y + b + size, b, b)}
    face, light, shadow, line = hexa(FACE), hexa(LIGHT), hexa(SHADOW), "#303030"
    chunks = []
    for part, (x, yy, w, h) in pieces.items():
        ident = f"{prefix}-{part}" if prefix else part
        body = rect(x, yy, w, h, face)
        if part != "center":
            if "top" in part:
                body += rect(x, yy, w, 1, line) + rect(x, yy + 1, w, 1, light)
            if "left" in part:
                body += rect(x, yy, 1, h, line) + rect(x + 1, yy + 1, 1, max(1, h - 1), light)
            if "right" in part:
                body += rect(x + w - 2, yy, 1, h, shadow) + rect(x + w - 1, yy, 1, h, line)
            if "bottom" in part:
                body += rect(x, yy + h - 2, w, 1, shadow) + rect(x, yy + h - 1, w, 1, line)
        chunks.append(f'<g id="{ident}" opacity="{alpha}">{body}</g>')
    return "\n".join(chunks)


def localized(key, values):
    out = {key: values["en"]}
    out.update({f"{key}[{lang}]": values[lang] for lang in LANGUAGES if lang != "en"})
    return out


def main():
    # the window frame and its buttons
    save(DECO / "decoration.svg", f'<svg {NS} width="72" height="216">' + window_frame("decoration", 0, True)
         + window_frame("decoration-inactive", 108, False) + "</svg>\n")
    for name in BUTTON_NAMES:
        button(name)
    rc = ["[General]", "TitleAlignment=Center", "TitleVerticalAlignment=Center", "Animation=0", "ActiveTextColor=0,0,0",
          "InactiveTextColor=80,80,80", "UseTextShadow=false", "[Layout]", "BorderLeft=4", "BorderRight=4", "BorderBottom=4",
          "TitleHeight=28", "TitleEdgeTop=0", "TitleEdgeBottom=0", "TitleEdgeLeft=9", "TitleEdgeRight=9",
          "TitleEdgeTopMaximized=0", "TitleEdgeBottomMaximized=0", "TitleEdgeLeftMaximized=9", "TitleEdgeRightMaximized=9",
          "TitleBorderLeft=8", "TitleBorderRight=8", "ButtonWidth=16", "ButtonHeight=16", "ButtonSpacing=6",
          "ButtonMarginTop=6", "ExplicitButtonSpacer=8", "PaddingTop=0", "PaddingBottom=0", "PaddingLeft=0", "PaddingRight=0"]
    save(DECO / f"{ID}rc", "\n".join(rc) + "\n")
    desktop = ["[Desktop Entry]", "Name=Kubabbar Glass 9"] + [f"Name[{lang}]=Kubabbar Glass 9" for lang in LANGUAGES if lang != "en"]
    desktop += [f"{k}={v}" for k, v in localized("Comment", DECORATION_COMMENT).items()]
    desktop += [f"X-KDE-PluginInfo-Name={ID}", "X-KDE-PluginInfo-Author=Daniel Ramos and EchoSystems AI studios",
                "X-KDE-PluginInfo-License=GPL-3.0-only", "X-KDE-PluginInfo-Version=0.1", "X-KDE-PluginInfo-EnabledByDefault=true"]
    save(DECO / "metadata.desktop", "\n".join(desktop) + "\n")
    names = localized("Name", {lang: "Kubabbar Glass 9" for lang in LANGUAGES})
    deco_meta = {"KPlugin": dict(Id=ID, **names, **localized("Description", DECORATION_COMMENT), Version="0.1",
                                 License="GPL-3.0-only", Authors=AUTHORS), "KPackageStructure": "KWin/Decoration"}
    save(ROOT / "kwin/decorations" / ID / "metadata.json", json.dumps(deco_meta, indent=2, ensure_ascii=False) + "\n")

    # the Plasma style at the family's glass; solid/ and opaque/ keep 91 %
    for path in ("widgets/background.svg", "widgets/translucentbackground.svg", "widgets/panel-background.svg",
                 "dialogs/background.svg", "widgets/tooltip.svg"):
        surface = path[:-len(".svg")]
        prefixes = list(SPARKY_BLACK_ALPHA[surface])
        for variant in ("", "translucent", "solid", "opaque"):
            body = "".join(plasma_frame(p, i * 80, level(surface, p, variant)) for i, p in enumerate(prefixes))
            body += '<rect id="hint-stretch-borders" width="1" height="1" x="90" fill="#000"/>'
            save(PLASMA / variant / path, f'<svg {NS} width="100" height="{len(prefixes) * 80}">{body}</svg>\n')
    style_meta = {"KPlugin": dict(Id=ID, **names, **localized("Description", STYLE_DESCRIPTION), Version="0.1",
                                  License="GPL-3.0-only", Authors=AUTHORS), "X-Plasma-API": "5.0"}
    save(PLASMA / "metadata.json", json.dumps(style_meta, indent=2, ensure_ascii=False) + "\n")
    save(PLASMA / "plasmarc", "[Settings]\nFallbackTheme=default\n[BlurBehindEffect]\nenabled=false\n[ContrastEffect]\nenabled=false\n")

    # the wallpaper: an original woven pattern in a light periwinkle, light enough for dark text through the glass
    base = hexa(WALLPAPER)
    lighter, darker = hexa(tuple(min(255, c + 6) for c in WALLPAPER)), hexa(tuple(c - 6 for c in WALLPAPER))
    up = "".join(f"M{x} 1080L{x + 1080} 0" for x in range(-1080, 1920, 12))
    down = "".join(f"M{x} 0L{x + 1080} 1080" for x in range(-1080, 1920, 12))
    wall = ROOT / "wallpapers" / ID / "contents/images"
    save(wall / "pattern.svg", f'<svg {NS} width="1920" height="1080"><rect width="1920" height="1080" fill="{base}"/>'
         f'<path d="{up}" stroke="{lighter}"/><path d="{down}" stroke="{darker}"/></svg>\n')
    subprocess.run(["rsvg-convert", str(wall / "pattern.svg"), "-o", str(wall / "1920x1080.png")], check=True)
    wall_meta = {"KPlugin": dict(Id=ID, **names, **localized("Description", WALLPAPER_DESCRIPTION), Version="0.1",
                                 License="GPL-3.0-only", Authors=AUTHORS)}
    save(ROOT / "wallpapers" / ID / "metadata.json", json.dumps(wall_meta, indent=2, ensure_ascii=False) + "\n")
    print("wrote", ID)


if __name__ == "__main__":
    main()
