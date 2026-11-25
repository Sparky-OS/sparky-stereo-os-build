sparky-stereo-welcome
The edition's pages in KDE's Welcome Center, the window a new account sees at its first login.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Daniel, 2026-11-18: "change sparky first run to our custom kde first run with all the elements sparkylinux one has, since our native DE is kde, I would rather follow this path".
So the first run is Plasma Welcome, KDE's Welcome Center, with the edition's pages in it.

How it opens
-------------
Plasma Welcome's kded module (kded_plasma-welcome) starts `plasma-welcome` at a login whose `plasma-welcomerc` has no `LastSeenVersion`, then writes the version into the person's own file, so the window opens once, at the first login of a new account, and not again; the person opens it from the menu whenever they like.
Earlier versions of sparky-stereo-info wrote a `LastSeenVersion` into `/etc/xdg/plasma-welcomerc` to keep the window closed; this package Breaks them, and sparky-stereo-info 20261125~sparky9~0 removes that file.

Where the files go
-------------
- `/usr/share/plasma/plasma-welcome/first-pages/`: the pages shown before KDE's own pages. The folder is read by the edition's plasma-welcome (6.7.4-1+stereo3d1, patch `0001-distro-pages-shown-first.patch`); KDE's own extension point, `extra-pages/`, puts a distribution's pages after its own five, right before the last one.
- `/usr/share/sparky-stereo-welcome/pictures/`: the stereo pictures, full side by side PNG with the `sTER` chunk.

The pages
-------------
- `00-SparkyStereoOS.qml`, the first page: the edition in one screen, the screens it shows 3D on, where Display Configuration is (a button opens it), the credit line.
- `01-PointAndType.qml`: the window under the pointer gets the keys; why, in Daniel Ramos's words; how to change it (a button opens Window Behavior).

Depth on a 3D screen
-------------
The pages use stereo-layer's own element depth, inside the person's limits, and set no separation of their own.
The picture of the first page is a stereo pair shown by `StereoPicture`, on a surface of its own below the window, its depth the artwork's.
The drawing of two windows on the pointer page is drawn once per eye by the edition's Qt Quick: the window under the pointer at the screen, the other one layer back (`StereoDepth.depth: -0.2`, the layer Stereo KWin gives the first window beneath the active one).
Words and buttons are the window's own, the same in both eyes.
A 2D screen shows the pages as they are, flat.

Build
-------------
OUT=/path/to/output ./build.sh (inside a container with python3, python3-pil, dpkg-dev and node-acorn; the pictures are cut from sparky-stereo-calamares-branding's slides by tools/make-pictures.py)

Credits
-------------
KDE's Welcome Center is by Felipe Kinoshita, Nate Graham and Oliver Beard and the KDE community.
SparkyLinux's first-run window, Sparky Welcome, is Paweł "pavroo" Pijanowski's work.
The picture is cut from the SparkyOS artwork's installer slide "any screen" (Daniel Ramos), the four screens only.
