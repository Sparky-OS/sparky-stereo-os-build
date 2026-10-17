sparky-stereo-calamares-branding
Sparky Stereo OS's installer slideshow: twenty-three slides in stereo 3D, flat on a 2D screen.

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
Twenty-three pictures of the SparkyOS artwork (installer-slides), in the order of the artwork's slides.json: welcome, desktop, movies, vr-films, science, photos, paint-and-edit, create-3d, web, deep-colour, any-screen, phone, throw-and-catch, sound, controllers, hardware, games, screensavers, variety, video-wallpaper, boot-and-lock, classic-look, certificates.
The pictures carry no text.
The words of each slide are QML text (qsTr) in show.qml, set at the screen plane over the picture's left column: the same pixels in both eyes, where the picture has no content that comes out of the screen.
show.qml is written by tools/make-slideshow.py from the approved texts (the artwork's slides.json), never retyped.

Translations
-------------
Calamares loads the branding's lang/calamares-sparky_<locale>.qm for the installer's language and falls back to the English source.
translations/ holds one source per language (en, de, pl, pt_BR, fr, ja, ko, zh_CN, zh_TW), made by tools/make-slideshow.py: English is the source language. The translations of 2026-10-16 are in translations/slides-20261016.json, one list per language in the source's order; tools/fill-ts.py writes them into the .ts files.
build.sh compiles a .qm (lrelease) only from a source that has finished translations, so a language with none shows English.
To add a language: translate the 69 strings in its .ts (Qt Linguist, or by hand, one <translation> per <source>), remove type="unfinished", and build.
A longer translation shrinks to fit the block; the block is laid out in the artwork's 1280 x 720 units and scaled with the picture.
