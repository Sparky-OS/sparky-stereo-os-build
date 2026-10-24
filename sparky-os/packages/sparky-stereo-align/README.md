Dolphin menu to align a stereo pair with Hugin
Adds "Align stereo pair" to Dolphin's right click menu on two pictures, and "Align the two views" on a JPS, MPO or PNS,
through Hugin's align_image_stack -S. The result is a new JPS, MPO or PNS with its own mark; the original is never touched.

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
python3, python3-pil, sparky-stereo-integration (>= 0.1.0)

Install:
-------------
Install the package with apt; the pack is data for hugin-tools and holds no code that links against it.
