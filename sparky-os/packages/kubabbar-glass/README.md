# Kubabbar Glass

Daniel’s second Sparky Stereo desktop look, with the identifier `kubabbar-glass`.
Everything is in `share/`, `bin/` and `lang/`; the design notes and the verification records are not public yet.

## The menu bar and dock variant

A third Look and Feel, `kubabbar-glass-menubar` (Kubabbar Glass, menu bar and dock), puts the application menu (Plasma's Global Menu) in a bar at the top after our own launcher star and the icons-only task manager in a floating centred dock; minimised windows fly into their icon with KWin's Magic Lamp (`kubabbar-glass-minimize squash` chooses Squash).

## What it is

The look of the Quick Settings window is the look of every application: Breeze controls, flat and quiet, in the Kubabbar Glass colours.
The other looks that were drawn stay as options: `kubabbar-glass-style fusion`, `kvantum` or `oxygen` (the default is `breeze`).
GTK 3 and GTK 4 programs follow through the `Kubabbar-Glass` theme, which `sparky-stereo-gtk-sync` selects from the KDE colour scheme; the Sparky Stereo Oxygen look gets the same through `Sparky-Stereo-Oxygen`.
The window buttons keep KDE’s layout and functions: the window menu and the all-desktops pin on the left; help, minimize, maximize or restore, and close on the right.
Only their drawing follows the look: square boxes with a small sign, the modernised Platinum form, drawn again from scratch.
Cursors, the splash, the SDDM login screen and the Look and Feel package are included; the Look and Feel applies everything in one step.
The 3D icon pilot is the Trash, empty and full, as stereo pairs in 16 bits per channel; `tools/icons3d` is the pipeline that makes the rest of the set.

Both Kubabbar Glass and Sparky Stereo Oxygen render widget backgrounds at 91 % alpha, leaving text, icons and controls unchanged.
KWin applies the edition’s translucency settings to windows: inactive windows and dialogs at 91 %, existing menu values, full screen excluded, blur and contrast off.
The active caption has a plain backing sized to its text, surrounded by original horizontal stripes.
There is no extra collapse box: rolling a window up is the title-bar wheel and the window menu, once our KWin shades Wayland windows.

Original code and geometry are copyright 2026 Daniel Ramos and EchoSystems AI studios, GPL-3.0-only; see LICENSE.
The Kvantum option is KvGnome’s shapes by Tsu Jan (GPL-3.0+), recoloured.
The GTK themes import the Breeze GTK shapes from `breeze-gtk-theme` (The KDE Developers, LGPL-2.1+) and do not copy them.
The derived Oxygen backgrounds retain The Oxygen Project’s GPL declaration, credits and licence texts.
Unresolved Sparky black and GNOME fill-ins and the restricted Glass icon set are not shipped.
See [About](ABOUT.md) for the inspiration credits.

## The name

Kubabbar Glass is our own name for this look, chosen by Daniel Ramos on 14 October 2026.
SparkyLinux names its releases after the sky and its oldest stories, and two of them come from Mesopotamia: Sparky 5 "Nibiru" and Sparky 9 "Tiamat", the release this edition is built on.
Sparky Stereo OS 9 is "Mashtabba", the Twins of the Babylonian star lists.
This look follows the same line: kù-babbar is the Sumerian word for silver, written with the signs for metal and shining.
The Mac OS 8 look it recalls was called Platinum, a metal the Sumerians never knew; its name comes from the Spanish platina, "little silver", so the Sumerian word for silver is the nearest homage.
Glass is for the translucency the whole edition shares: inactive windows, dialogs and widget backgrounds at 91 % alpha.
Niels van Mourik (Platinum for Aurorae and Look and Feel) and Zinjanthr0pus (QPlatinum) made the KDE themes that inspired it; their names stay theirs, and the artwork here is original.

Sources: [SparkyLinux code names](https://wiki.sparkylinux.org/doku.php/code_names) and [kù-babbar, ePSD2 lemma kugbabbar](https://en.wiktionary.org/wiki/%F0%92%86%AC%F0%92%8C%93).
