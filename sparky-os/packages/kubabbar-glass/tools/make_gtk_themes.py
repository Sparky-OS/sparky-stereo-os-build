#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate share/themes: GTK 3 and GTK 4 themes for both looks, on the Breeze GTK shapes and the KDE colour scheme."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
THEMES = {
    "Kubabbar-Glass": ("Breeze", ROOT / "share/color-schemes/kubabbar-glass.colors", "Kubabbar Glass"),
    "Sparky-Stereo-Oxygen": ("Breeze-Dark", pathlib.Path("/usr/share/color-schemes/OxygenDark.colors"), "Sparky Stereo Oxygen"),
}
for name, (base, scheme, title) in THEMES.items():
    for gtk in ("3.0", "4.0"):
        directory = ROOT / "share/themes" / name / ("gtk-" + gtk)
        directory.mkdir(parents=True, exist_ok=True)
        base_css = "/usr/share/themes/%s/gtk-%s/gtk.css" % (base, gtk)
        colors = subprocess.run([sys.executable, str(ROOT / "tools/kde2gtk_colors.py"), str(scheme), base_css],
                                check=True, capture_output=True, text=True).stdout
        (directory / "colors.css").write_text(colors)
        (directory / "gtk.css").write_text(
            "/* SPDX-License-Identifier: GPL-3.0-only */\n"
            "/* %s: the %s shapes (breeze-gtk, LGPL-2.1+, The KDE Developers) in this look's colours. */\n"
            '@import url("file:///usr/share/themes/%s/gtk-%s/gtk.css");\n'
            '@import url("colors.css");\n' % (title, base, base, gtk))
    (ROOT / "share/themes" / name / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=%s\nComment=%s widgets for GTK 3 and GTK 4, in the colours of the KDE scheme\n"
        "Encoding=UTF-8\n\n[X-GNOME-Metatheme]\nGtkTheme=%s\nIconTheme=oxygen\n" % (name, title, name))
print("themes written")
