# Kubabbar Glass

Milestone 1 drawings for Daniel’s second Sparky Stereo desktop look, with the identifier `kubabbar-glass`.
The colour scheme, Aurorae QML decoration, Plasma backgrounds and original wallpaper are in `share/`.
The Look and Feel package applies these first drawings; application widgets and GTK follow in milestone 2.
See [the design study](study/design.md), [icon provenance](study/icons.md) and [verification](study/progress.md).

Both Kubabbar Glass and Sparky Stereo Oxygen render widget backgrounds at 91 % alpha, leaving text, icons and controls unchanged.
KWin applies the edition’s translucency settings to windows: inactive windows and dialogs at 91 %, existing menu values, full screen excluded, blur and contrast off.
The active caption has a plain backing sized to its text, surrounded by original horizontal stripes.
The third window box currently minimizes as a placeholder.
Plasma on Wayland does not shade Wayland windows; Daniel will choose shading in our KWin, minimize, or another action.
This open choice does not block milestone 1.

Original code and geometry are copyright 2026 Daniel Ramos and EchoSystems AI studios, GPL-3.0-only; see LICENSE.
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
