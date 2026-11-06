Dolphin entry to run a Windows program or installer with Wine
Adds "Run with Wine" to Dolphin's right click menu on Windows programs and installers (.exe and .msi): it starts the file with Wine, in its folder. No default handler is registered, so a double click never runs a downloaded Windows program.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
sparky-stereo-integration (>= 0.1.0)

Install:
-------------
Install the package with apt; the pack is data for wine and holds no code that links against it.
