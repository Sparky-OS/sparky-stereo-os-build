#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate share/themes: GTK 3 and GTK 4 themes for both looks, on the Breeze GTK shapes and the KDE colour scheme."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
THEMES = {
    "Kubabbar-Glass": ("Breeze", ROOT / "share/color-schemes/kubabbar-glass.colors", "Kubabbar Glass"),
    "Sparky-Stereo-Oxygen": ("Breeze", ROOT / "tools/color-schemes/SparkyStereoOxygen.colors", "Sparky Stereo Oxygen"),
    "Sparky-Stereo-Oxygen-Dark": ("Breeze-Dark", ROOT / "tools/color-schemes/SparkyStereoOxygenDark.colors", "Sparky Stereo Oxygen Dark"),
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
    if name.startswith("Sparky-Stereo-Oxygen"):
        # GTK 2 programs take the session's one theme name too (XSETTINGS, ~/.gtkrc-2.0): its GTK 2 part is KDE's Oxygen
        # engine (gtk2-engines-oxygen), so they wear Oxygen as Qt programs do; GTK 3 and 4 keep the parts above.
        gtk2 = ROOT / "share/themes" / name / "gtk-2.0"
        gtk2.mkdir(parents=True, exist_ok=True)
        (gtk2 / "gtkrc").write_text("# %s for GTK 2: KDE's Oxygen engine (oxygen-gtk)\n"
                                    'include "/usr/share/themes/oxygen-gtk/gtk-2.0/gtkrc"\n' % title)
    (ROOT / "share/themes" / name / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=%s\nComment=%s widgets for GTK 3 and GTK 4, in the colours of the KDE scheme\n"
        "Encoding=UTF-8\n\n[X-GNOME-Metatheme]\nGtkTheme=%s\nIconTheme=oxygen\n" % (name, title, name))
print("themes written")
