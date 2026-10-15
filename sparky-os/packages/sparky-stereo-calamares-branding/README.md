sparky-stereo-calamares-branding
Sparky Stereo OS's installer slideshow: six slides in stereo 3D, flat on a 2D screen.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

Dependencies:
-------------
calamares; for the slides in 3D, the build with the branding setting slideshowWindow (3.4.3~sparky9~4-1+stereo3d1 or later, a Recommends); any other calamares shows each slide as its left view
libstereo-layer1 (>= 1.4.1), which brings the QML module org.sparky.stereo

Build:
-------------
OUT=/path/in/workspace/pending-pack ./build.sh (inside a container)

Install:
-------------
su
OUT=/path/to/packages ./install.sh

Uninstall:
-------------
su
./install.sh uninstall

How it works
-------------
Calamares shows its slides from the branding's show.qml, once the installation starts.
Each slide is a StereoPicture of stereo-layer, which hands the compositor the picture as full side by side, left eye first, on a surface of its own, declared once.
The rest of the installer is the window's own surface and stays 2D, identical in both eyes.
On a screen that shows one eye the slide is its left view.

A QML slideshow normally runs inside a QQuickWidget, which has no surface of the windowing system to itself, so a stereo picture cannot work there.
The branding sets slideshowWindow, which the patched calamares package reads: the same QML runs in a QQuickView embedded in the page.
A calamares without the setting ignores it and shows each slide as its left view.

Why the branding is named sparky
-------------
settings.conf in SparkyLinux's calamares package names the branding sparky, and a settings.conf in /etc/calamares would replace the whole file.
Calamares looks for a branding in /etc/calamares/branding before /usr/share/calamares/branding, so the package links /etc/calamares/branding/sparky to its own folder.
SparkyLinux's files stay as they are, and removing this package gives the original branding back.
The settings of the users module are separate (sparky-stereo-user-groups) and are not touched.

The slides
-------------
Six pictures of the SparkyOS artwork (installer-slides): welcome, movies, science, photos, deep colour, any screen.
Their text is part of the pictures, in English.
Another language is another set of pictures, built from the artwork's recipes and named slideN-name.pns.
