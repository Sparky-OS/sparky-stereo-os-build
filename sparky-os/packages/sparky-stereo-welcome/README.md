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
Sparky Welcome's own first-run start (`/etc/xdg/autostart/sparky-welcome-first.desktop`, a unit made by systemd's XDG autostart generator) is skipped where the Welcome Center carries this package's first page: `/usr/lib/systemd/user/app-sparky\x2dwelcome\x2dfirst@autostart.service.d/sparky-stereo-welcome.conf` (`ConditionPathExists=!` the first page). Sparky Welcome stays installed and in the menu; removing this package gives its first run back.
In a live session a live-config hook (`/usr/lib/live/config/1187-sparky-stereo-welcome`) writes the live user's own `plasma-welcomerc` (`LiveEnvironment=true`, `LiveInstaller=calamares`): the Welcome Center then opens in its live mode, the installer's page first.

Where the files go
-------------
- `/usr/share/plasma/plasma-welcome/first-pages/`: the pages shown before KDE's own pages. The folder is read by the edition's plasma-welcome (6.7.4-1+stereo3d2, patch `0001-distro-pages-shown-first.patch`); KDE's own extension point, `extra-pages/`, puts a distribution's pages after its own five, right before the last one.
- `/usr/share/plasma/plasma-welcome/extra-pages/`: the pages after KDE's own, before its last page.
- `/usr/share/sparky-stereo-welcome/pictures/`: the stereo pictures, full side by side PNG with the `sTER` chunk.
- `/usr/bin/sparky-stereo-welcome-upgrade`: the SparkyLinux page's Upgrade, as Sparky Welcome's own handler runs it.
- `/etc/xdg/plasma-workspace/env/sparky-stereo-welcome-touch.sh` and `/usr/share/sparky-stereo-welcome/touch-screen/xdg/`: where the hardware layer found a touch screen of the computer's own, `plasma-welcomerc [Distribution] TouchScreen=true` for the touch page's other condition (`Welcome.Distro.flag`, plasma-welcome 6.7.4-1+stereo3d2).
- `/usr/share/locale/LANG/LC_MESSAGES/sparky-stereo-welcome.mo`: the words in pt_BR, es, fr, de, pl, ja, ko, zh_CN and zh_TW (from `po/`, made by `tools/extract-messages.sh`).

The pages
-------------
- `00-SparkyStereoOS.qml`, the first page: the edition in one screen, the screens it shows 3D on, where Display Configuration is (a button opens it), the credit line.
- `01-PointAndType.qml`: the window under the pointer gets the keys; why, in Daniel Ramos's words; how to change it (a button opens Window Behavior).
- `extra-pages/01-TouchAndTabletMode.qml`: what a tap does where the mouse keeps its own click setting, as measured, and the on-screen keyboard and the panels in tablet mode; buttons for General Behavior and Virtual Keyboard. `show: true`; `show: Welcome.Distro.flag("TouchScreen")` shows it only on a computer with a touch screen of its own.
- `extra-pages/02-SparkyWorld.qml`: every element of Sparky Welcome, with its own address or command.
- `extra-pages/03-HelpTest.qml`: what the screens can do in 3D (`stereo-display-info`), copied; the edition's tracker.

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
The German, Spanish and Polish words of Sparky Welcome's own buttons and headings are its translators' (its files were first made by Piotr "MoroS" Mrożek; the translators as its copyright file names them: Roy, jidan, Goro86, depaz, Jouko Tiilikainen, nemomen, Yodel Sinatra, ChourS, XalisRatt).
