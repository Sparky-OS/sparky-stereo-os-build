#!/usr/bin/env python3
"""Kubabbar Glass 9's Look and Feel (the default layout: the person's own panels are kept). It applies in one click the
Kvantum application style, the colour scheme, the Plasma style, the window decoration with the family's buttons and
layout (Daniel, 2026-10-14: "left: app menu; right: minimize, maximize/restore, close"), the family's icons and cursors,
the family's loading screen and the wallpaper. It carries no fonts: Plasma's Look and Feel manager removes a person's
own value of every key it applies (KLookAndFeelManager::writeNewDefaults, revertToDefault), so the fonts and the
Kvantum theme reach the session through kubabbar-glass-9-sync, which writes only the look's own defaults store.
GPL-3.0-only."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from platinum9 import LANGUAGES  # noqa: E402
from strings9 import LOOK_DESCRIPTION  # noqa: E402

ROOT = Path(__file__).resolve().parents[1] / "share/plasma/look-and-feel/kubabbar-glass-9"

DEFAULTS = """[kdeglobals][KDE]
widgetStyle=kvantum

[kdeglobals][General]
ColorScheme=kubabbar-glass-9

[kdeglobals][Icons]
Theme=kubabbar-glass-stereo

[plasmarc][Theme]
name=kubabbar-glass-9

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=kubabbar-glass-9
ButtonsOnLeft=MS
ButtonsOnRight=HIAX

[Wallpaper]
Image=kubabbar-glass-9

[kcminputrc][Mouse]
cursorTheme=kubabbar-glass-cursors

[ksplashrc][KSplash]
Engine=KSplashQML
Theme=kubabbar-glass
"""


def main():
    meta = {"KPlugin": {"Id": "kubabbar-glass-9", "Name": "Kubabbar Glass 9"}}
    meta["KPlugin"].update({f"Name[{lang}]": "Kubabbar Glass 9" for lang in LANGUAGES if lang != "en"})
    meta["KPlugin"]["Description"] = LOOK_DESCRIPTION["en"]
    meta["KPlugin"].update({f"Description[{lang}]": LOOK_DESCRIPTION[lang] for lang in LANGUAGES if lang != "en"})
    meta["KPlugin"].update({"Version": "0.1", "License": "GPL-3.0-only",
                            "Authors": [{"Name": "Daniel Ramos and EchoSystems AI studios"}]})
    meta["KPackageStructure"] = "Plasma/LookAndFeel"
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "metadata.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    (ROOT / "contents").mkdir(exist_ok=True)
    (ROOT / "contents/defaults").write_text(DEFAULTS)
    print("wrote", ROOT)


if __name__ == "__main__":
    main()
