sparky-stereo-service-defaults
Working defaults for services that fail at every boot on a fresh Sparky Stereo OS.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Each file is a systemd drop-in for one service of another package. A service is never removed or masked: it is configured so it works, or skipped until what it needs is there. Each drop-in says why, and each cause is reported to the package that owns it.

Dependencies:
-------------
systemd

Build:
-------------
OUT=/path/to/output ./build.sh (inside debian:testing)
