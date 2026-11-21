#!/usr/bin/env python3
"""mo-check.py LANG...: for each language, the module's gettext catalogue as Python finds it (gettext.translation with that
language, the installed /usr/share/locale), and the six sentences it gives."""
import gettext, sys
ids = ["Enable 3D", "3D display settings...", "The display settings could not be opened: %s",
       "This figure is shown flat: its window cannot hold a 3D area. The Tk and Qt windows on X11 can.",
       "This figure is shown flat: this desktop does not show 3D areas inside windows.",
       "This desktop does not offer depth limits, so both eyes show the same picture."]
for lang in sys.argv[1:]:
    try:
        t = gettext.translation("stereo-matplotlib", languages=[lang])
        print(lang, "catalogue", t._catalog.get("", "").split("Language:")[-1].split("\\n")[0].strip() if t._catalog.get("") else "",
              *["%s => %s" % (i, t.gettext(i)) for i in ids], sep="\t")
    except OSError as e:
        print(lang, "NOT FOUND", e)
