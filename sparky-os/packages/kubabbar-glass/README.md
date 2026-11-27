# Kubabbar Glass

Daniel’s second Sparky Stereo desktop look, with the identifier `kubabbar-glass`.
Everything is in `share/`, `bin/` and `lang/`; the design notes and the verification records are not public yet.

## The menu bar and dock variant

A third Look and Feel, `kubabbar-glass-menubar` (Kubabbar Glass, menu bar and dock), puts the application menu (Plasma's Global Menu) in a bar at the top after our own launcher star and the icons-only task manager in a floating centred dock; minimised windows fly into their icon with KWin's Magic Lamp (`kubabbar-glass-minimize squash` chooses Squash).

## What it is

The look of the Quick Settings window is the look of every application: Breeze controls, flat and quiet, in the Kubabbar Glass colours.
The other looks that were drawn stay as options: `kubabbar-glass-style fusion`, `kvantum` or `oxygen` (the default is `breeze`).
GTK 3 and GTK 4 programs follow through the `Kubabbar-Glass` theme, which `sparky-stereo-gtk-sync` selects from the KDE colour scheme; the Sparky Stereo Oxygen look gets the same through `Sparky-Stereo-Oxygen` (light) or `Sparky-Stereo-Oxygen-Dark` (dark).
The sync recognizes `SparkyStereoOxygen`, `SparkyStereoOxygenDark`, the legacy `Oxygen`/`OxygenDark`, and `kubabbar-glass`; other schemes keep the Breeze light/dark selection.
The window buttons keep KDE’s layout and functions: the window menu and the all-desktops pin on the left; help, minimize, maximize or restore, and close on the right.
Only their drawing follows the look: square boxes with a small sign, the modernised Platinum form, drawn again from scratch.
Cursors, the splash, the SDDM login screen and the Look and Feel package are included; the Look and Feel applies everything in one step.
The splash draws the clean background of the boot splash and, in its window (the menu bar look: in the middle of the screen), the Sparky logo when the system has it (`/usr/share/pixmaps/sparkyos.png`, from sparkyos-artwork; the theme never carries it), the theme's name and the system's name and version from os-release; without the logo the theme's name stands in its place, and without os-release the theme's name alone.
On a 3D screen the background stays at the screen and the window, or the middle, stands at the person's popped limit.
The 3D icon pilot is the Trash, empty and full, as stereo pairs in 16 bits per channel; `tools/icons3d` is the pipeline that makes the rest of the set.

Both Kubabbar Glass and Sparky Stereo Oxygen draw the panel, pop-ups, notifications, tooltips and widget backgrounds at Sparky Black's levels, each look in its own colours, leaving text, icons and controls unchanged (Daniel, 2026-10-15: "Sparky Black transluscent levels transplanted to both sparky stereo themes").
The levels, as KSvg draws Sparky Black's Plasma style (8-bit alpha): the panel 129 at the bottom edge, 44 at the top and the sides, 164 without an edge; pop-ups, notifications and tooltips 157; widget backgrounds 80, translucent ones 60.
A panel the person sets to Opaque (and an Adaptive one beside a maximized window) keeps 232, 91 %.
KWin applies the edition’s translucency settings to windows: inactive windows and dialogs at 91 %, existing menu values, full screen excluded, blur and contrast off.
The active caption has a plain backing sized to its text, surrounded by original horizontal stripes.
There is no extra collapse box: rolling a window up is the title-bar wheel and the window menu, once our KWin shades Wayland windows.

Original code and geometry are copyright 2026 Daniel Ramos and EchoSystems AI studios, GPL-3.0-only; see LICENSE.
The Kvantum option is KvGnome’s shapes by Tsu Jan (GPL-3.0+), recoloured.
The GTK themes import the Breeze GTK shapes from `breeze-gtk-theme` (The KDE Developers, LGPL-2.1+) and do not copy them.
The derived Oxygen backgrounds retain The Oxygen Project’s GPL declaration, credits and licence texts.
Unresolved Sparky black and GNOME fill-ins and the restricted Glass icon set are not shipped.
See [About](ABOUT.md) for the inspiration credits.

## Kubabbar Glass 9

Kubabbar Glass 9 (`kubabbar-glass-9`, its own package) is the family's classic variant: where Kubabbar Glass takes the flat controls of the Quick Settings window, every control here is drawn in a classic bevelled form, recalling Mac OS 9's Platinum appearance, in the family's glass.
- **Controls, Qt 6 and Qt 5:** Kvantum themes drawn by `tools/make_kvantum9.py`: the default button ringed, bevel and tool buttons, check boxes, radio buttons, pop-up menus and combo boxes, text fields with a focus ring, spin boxes, sliders, striped progress bars, rounded tabs, engraved group boxes, list headers, disclosure triangles, menus and the menu bar, tooltips, and scroll bars with a gripped scroll box whose size follows the page.
- **Scroll arrows:** together at the end of the scrollbar by default; `kubabbar-glass-9-scrolling apart` puts them at both ends (the classic Appearance panel offered both). The arrows together need the edition's Kvantum (`sparky-os/packages/kvantum`, the `scroll_arrows_together` key).
- **Accents:** the colour schemes Kubabbar Glass 9 (lavender, the default), Graphite, Ivy, Rose, Gold and Teal colour the menu highlight, the scroll box, the progress bar and the text highlight; every text reads at 4.5:1 or more on its backgrounds.
- **Window frame:** a pinstriped active title bar and a plain inactive one, with the family's square buttons, layout and functions (the window menu on the left; minimize, maximize or restore, close on the right).
- **Plasma style:** the panel, pop-ups, tooltips and widget backgrounds at the family's glass, read from `tools/glass_levels.py`, the one place both looks take their levels from.
- **Fonts:** the look names Charcoal (system font, menus, window titles), Geneva (small and toolbar fonts) and Monaco (fixed font) and uses them where they are installed; it never ships them. Where they are missing, `fontconfig/conf.avail/45-kubabbar-glass-9.conf` gives the free fonts measured nearest to them glyph by glyph: Noto Sans Display (bold, Charcoal's weight), DejaVu Sans and Inconsolata.
- **One click, and your own choices kept:** the Look and Feel applies the style, colours, Plasma style, decoration, icons, cursors, loading screen and wallpaper. Plasma's Look and Feel manager removes a person's own value of every key it applies, so the fonts and the Kvantum theme travel another way: `kubabbar-glass-9-sync` writes them into the look's own defaults store (`~/.config/kdedefaults`) while the look is applied, never into your own settings, and removes exactly what it wrote when another look is applied. Your own fonts and your own Kvantum choice always win.
- **Proof:** `rig/m9/rerun.sh IMAGE OUT` runs every check again from the packages installed in a proof rig image: the session helper's tests, the font route through `plasma-apply-lookandfeel`, the controls in Qt 6 and Qt 5 beside Kubabbar Glass, and fresh logins in which the glass of every surface, each window's depth on a 3D output and the fonts the session draws are measured; it ends with one PASS or FAIL line per row.

- **GTK 2, 3 and 4:** the themes `Kubabbar-Glass-9` and one per accent (`-Graphite`, `-Ivy`, `-Rose`, `-Gold`, `-Teal`), in the `sparky-stereo-gtk` package, draw the same pictures as the Kvantum themes (`tools/make_gtk9.py`): GTK 2 on its pixmap engine, GTK 3 and GTK 4 over the Breeze GTK shapes in the scheme's colours. `sparky-stereo-gtk-sync` picks the theme of the colour scheme, and its `-Apart` twin when the scroll arrows are at both ends. GTK 4's own library has no scroll arrows; the edition's GTK 4 (gtk4 +stereo3d4) gives its scroll bars GTK 3's four steppers, shown only when a theme gives them a size, and the GTK 4 themes show the two of the chosen placement.
- **Scroll bars always visible:** as the Qt scroll bars always show (Kvantum's `transient_scrollbar=false`), so do GTK's: for the 9's themes `sparky-stereo-gtk-sync` turns GTK's overlay scrolling off (`gtk-overlay-scrolling=false` in GTK 3's and GTK 4's `settings.ini`, and the GSettings key `org.gnome.desktop.interface overlay-scrolling`, which GTK reads through the settings portal on Wayland). Your own value of either is kept: the script records what it wrote, and when another look is applied it removes only what it wrote and still finds there.
- **Menu bar layout:** `kubabbar-glass-9-menubar` is the family's menu bar and dock with Plasma's window list at the bar's right end, in the place of the classic Application menu. Plasma applies a Look and Feel's layout only when the person asks for it ("Desktop and window layout" on the Global Theme page, `plasma-apply-lookandfeel --resetLayout`), so either layout keeps a person's own panels otherwise.
- **Loading screen:** after the classic startup screen, under the family's rules: the boot splash's clean background, and in the middle a classic box at the family's glass with the Sparky logo where the system has it (the theme's name in its place otherwise), the system's name and version from os-release in big black letters, the theme's name and a classic progress bar. On a 3D screen the background stays at the screen and the box stands at the person's popped limit.
- **Login screen:** an SDDM theme after the classic Multiple Users window: choose your name in the list of the computer's people or type it, then log in, and the password is asked in a box of its own. Its texts are SDDM's own, translated by SDDM, and two of ours in the ten languages. On a 3D screen the pattern behind sinks, the window is at the screen and the password box and the session's menu stand popped. The edition's login manager is Plasma Login Manager; this theme is for a person who uses SDDM.

## The name

Kubabbar Glass is our own name for this look, chosen by Daniel Ramos on 14 October 2026.
SparkyLinux names its releases after the sky and its oldest stories, and two of them come from Mesopotamia: Sparky 5 "Nibiru" and Sparky 9 "Tiamat", the release this edition is built on.
Sparky Stereo OS 9 is "Mashtabba", the Twins of the Babylonian star lists.
This look follows the same line: kù-babbar is the Sumerian word for silver, written with the signs for metal and shining.
The Mac OS 8 look it recalls was called Platinum, a metal the Sumerians never knew; its name comes from the Spanish platina, "little silver", so the Sumerian word for silver is the nearest homage.
Glass is for the translucency the whole edition shares: inactive windows and dialogs at 91 % alpha, and the panel, pop-ups, tooltips and widget backgrounds at Sparky Black's levels.
Kubabbar Glass 9 adds a 9 for the Mac OS 9 look it recalls (Apple, 1999 to 2001), and for Sparky 9 "Tiamat", with Sparky Stereo OS 9 "Mashtabba" beneath it.
Niels van Mourik (Platinum for Aurorae and Look and Feel) and Zinjanthr0pus (QPlatinum) made the KDE themes that inspired it; their names stay theirs, and the artwork here is original.

Sources: [SparkyLinux code names](https://wiki.sparkylinux.org/doku.php/code_names) and [kù-babbar, ePSD2 lemma kugbabbar](https://en.wiktionary.org/wiki/%F0%92%86%AC%F0%92%8C%93).

Credits for Kubabbar Glass 9: Niels van Mourik (Platinum) and Zinjanthr0pus (QPlatinum) as the KDE themes that inspired the family, none of their files used; Tsu Jan's Kvantum, which draws the controls; the free fonts measured nearest to the classic ones, credited from their own files: Noto Sans Display (Google Inc., designed by the Monotype Design Team, SIL Open Font License 1.1), DejaVu Sans (Bitstream, Inc., Tavmjong Bah and the DejaVu fonts team; Bitstream Vera licence, the DejaVu changes in the public domain) and Inconsolata (The Inconsolata Project Authors, designed by Raph Levien, Cyreal and Brenton Simpson, SIL Open Font License 1.1); Mac OS 9 (Apple, 1999 to 2001) as the inspiration only.
