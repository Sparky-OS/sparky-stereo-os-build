#!/usr/bin/env python3
"""Original geometric artwork for the classic appearance study, GPL-3.0-only."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "share"
DECO = ROOT / "aurorae/themes/kubabbar-glass"
PLASMA = ROOT / "plasma/desktoptheme/kubabbar-glass"
NS = 'xmlns="http://www.w3.org/2000/svg"'
# Qt's 256-step painter opacity must render the nearest 8-bit alpha to 91%: 232.
BACKGROUND_ALPHA = 233 / 256


def save(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def rect(x, y, w, h, color, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{color}" {extra}/>'


def frame(prefix, y, top=4, alpha=1, stripes=False, transparent=False):
    b, size = 4, 64
    chunks = []
    pieces = {"topleft": (0, y, b, top), "top": (b, y, size, top),
              "topright": (b + size, y, b, top), "left": (0, y + top, b, size),
              "center": (b, y + top, size, size), "right": (b + size, y + top, b, size),
              "bottomleft": (0, y + top + size, b, b), "bottom": (b, y + top + size, size, b),
              "bottomright": (b + size, y + top + size, b, b)}
    for part, (x, yy, w, h) in pieces.items():
        ident = f"{prefix}-{part}" if prefix else part
        opacity = 0 if transparent and part == "center" else 1
        body = rect(x, yy, w, h, "#d8d9d5", f'opacity="{opacity}"')
        if part != "center":
            if "top" in part:
                body += rect(x, yy, w, 1, "#414740") + rect(x, yy + 1, w, 1, "#ffffff")
                if stripes and part == "top":
                    for row in range(6, top - 3, 3):
                        body += rect(x, yy + row, w, 1, "#abb0a8")
                        body += rect(x, yy + row + 1, w, 1, "#eff0ec")
            if "left" in part:
                body += rect(x, yy, 1, h, "#414740") + rect(x + 1, yy + 1, 1, max(1, h - 1), "#ffffff")
            if "right" in part:
                body += rect(x + w - 2, yy, 1, h, "#858d83") + rect(x + w - 1, yy, 1, h, "#414740")
            if "bottom" in part:
                body += rect(x, yy + h - 2, w, 1, "#858d83") + rect(x, yy + h - 1, w, 1, "#414740")
        chunks.append(f'<g id="{ident}" opacity="{alpha}">{body}</g>')
    return "\n".join(chunks)


BUTTON_STATES = ("active", "hover", "pressed", "inactive", "hover-inactive", "pressed-inactive", "deactivated", "deactivated-inactive")
BUTTON_NAMES = ("close", "maximize", "restore", "minimize", "alldesktops", "help", "keepabove", "keepbelow", "shade", "appmenu")


def glyph(name, x, ink, face, toggled):
    """Glyphs inside the 16 px box, drawn from the QPlatinum idea (a square box with a small sign), not from its files."""
    sw = 'stroke-width="1.5" fill="none" stroke-linecap="square" stroke-linejoin="miter"'
    if name == "close":
        return f'<path d="M{x+5} 5l6 6m0 -6l-6 6" stroke="{ink}" {sw}/>'
    if name == "maximize":
        return f'<rect x="{x+4.5}" y="4.5" width="7" height="7" stroke="{ink}" {sw}/>'
    if name == "restore":
        return (f'<rect x="{x+3.5}" y="6.5" width="6" height="6" stroke="{ink}" {sw}/>'
                f'<path d="M{x+6} 5.5h5.5v5.5" stroke="{ink}" {sw}/>')
    if name == "minimize":
        return f'<path d="M{x+4.5} 11h7" stroke="{ink}" {sw}/>'
    if name == "shade":
        return f'<path d="M{x+4.5} 5h7" stroke="{ink}" {sw}/>'
    if name == "alldesktops":
        fill = ink if toggled else "none"
        return f'<circle cx="{x+8}" cy="8" r="3" stroke="{ink}" fill="{fill}" stroke-width="1.5"/>'
    if name == "help":
        return (f'<path d="M{x+5.5} 6.2a2.5 2.2 0 1 1 3.6 2c-.8.5-1.1.9-1.1 1.8" stroke="{ink}" {sw}/>'
                f'<rect x="{x+7.3}" y="11.2" width="1.5" height="1.5" fill="{ink}"/>')
    if name == "keepabove":
        return f'<path d="M{x+4.5} 10l3.5 -4l3.5 4" stroke="{ink}" {sw.replace('fill="none"', f'fill="{ink}"' if toggled else 'fill="none"')}/>'
    if name == "keepbelow":
        return f'<path d="M{x+4.5} 6l3.5 4l3.5 -4" stroke="{ink}" {sw.replace('fill="none"', f'fill="{ink}"' if toggled else 'fill="none"')}/>'
    return "".join(rect(x + 4, row, 8, 1.5, ink) for row in (4.5, 7.5, 10.5))


def button(name):
    chunks = []
    defs = ('<defs><linearGradient id="face" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4f6ef"/>'
            '<stop offset="1" stop-color="#cfd4c6"/></linearGradient>'
            '<linearGradient id="hover" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/>'
            '<stop offset="1" stop-color="#dfe4d6"/></linearGradient>'
            '<linearGradient id="pressed" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#aab3a2"/>'
            '<stop offset="1" stop-color="#c4cbbc"/></linearGradient></defs>')
    for toggled in (False, True):
        for idx, state in enumerate(BUTTON_STATES):
            x = idx * 22
            slot = x + (176 if toggled else 0)
            pressed, hover = "pressed" in state, "hover" in state
            fill = "url(#pressed)" if pressed else "url(#hover)" if hover else "url(#face)"
            dead = state in ("inactive", "deactivated", "deactivated-inactive")
            body = f'<rect x="{slot+.5}" y=".5" width="15" height="15" rx="3" fill="{fill}" stroke="{"#7f8a76" if dead else "#424a3e"}"/>'
            if not pressed:
                body += f'<path d="M{slot+3} 1.5h10" stroke="#ffffff" stroke-width="1" opacity="0.9"/>'
            ink = "#929a8c" if dead else "#2b3526"
            body += glyph(name, slot, ink, fill, toggled)
            chunks.append(f'<g id="{"on-" if toggled else ""}{state}-center">{body}</g>')
    save(DECO / f"{name}.svg", f'<svg {NS} width="352" height="16">' + defs + "".join(chunks) + '</svg>\n')


def main():
    save(DECO / "decoration.svg", f'<svg {NS} width="72" height="212">' + frame("decoration", 0, 28, stripes=True, transparent=True) + frame("decoration-inactive", 108, 28, transparent=True) + '</svg>\n')
    for name in BUTTON_NAMES:
        button(name)
    for path in ("widgets/background.svg", "widgets/translucentbackground.svg", "widgets/panel-background.svg", "dialogs/background.svg", "widgets/tooltip.svg"):
        prefixes = [""]
        if "panel" in path:
            prefixes = ["", "north", "south", "east", "west"]
        body = "".join(frame(p, i * 80, alpha=BACKGROUND_ALPHA) for i, p in enumerate(prefixes))
        body += '<rect id="hint-stretch-borders" width="1" height="1" x="90" fill="#000"/>'
        for variant in ("", "translucent", "solid", "opaque"):
            save(PLASMA / variant / path, f'<svg {NS} width="100" height="{len(prefixes)*80}">{body}</svg>\n')
    vertical = "".join(f"M{x} 0v1080" for x in range(0, 1920, 8))
    horizontal = "".join(f"M0 {y}h1920" for y in range(0, 1080, 8))
    save(ROOT / "wallpapers/kubabbar-glass/contents/images/pattern.svg", f'<svg {NS} width="1920" height="1080"><rect width="1920" height="1080" fill="#7e8f86"/><path d="{vertical}" stroke="#819289"/><path d="{horizontal}" stroke="#7b8c83"/></svg>\n')
    wallpaper = ROOT / "wallpapers/kubabbar-glass/contents/images"
    subprocess.run(["rsvg-convert", str(wallpaper / "pattern.svg"), "-o", str(wallpaper / "1920x1080.png")], check=True)
    meta = {"KPlugin": {"Id": "kubabbar-glass", "Name": "Kubabbar Glass", "Description": "Original classic desktop appearance study", "Version": "0.2", "License": "GPL-3.0-only", "Authors": [{"Name": "Daniel Ramos and EchoSystems AI studios"}]}, "X-Plasma-API": "5.0"}
    save(PLASMA / "metadata.json", json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
