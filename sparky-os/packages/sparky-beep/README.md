Sparky Beep
Provides beep support for a few services of server edition.

Copyright (C) 2018-2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Source:
-------------
https://github.com/Sparky-OS/sparky-beep (the program, its debian/ and its tests)

Dependencies:
-------------
bash
bc
beep
systemd

Build:
-------------
IMAGE=<debian:testing image with debhelper, dpkg-dev, gcc> SRC=<clone> ./build.sh   (the package lands in /K3D/temp/sparky-os/repo, the source package in repo/source)
Tests: bats tests/ in the clone (237 tests, debian:testing, 2026-10-14)
