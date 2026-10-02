Sparky Stereo Time
Sets chrony's time sources from the timezone: the country's official service, with NTS where it offers it, or Debian's pool where the country has none.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
chrony

Build:
-------------
./build.sh   (the package lands in /K3D/temp/sparky-os/repo, or in $OUT)

Use:
-------------
sparky-stereo-time --print --zone America/Sao_Paulo
sudo sparky-stereo-time        (writes /etc/chrony/sources.d/sparky-stereo.sources)

Test:
-------------
test/run-tests.sh   (in a debian:testing container, with chrony installed)
